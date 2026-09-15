'use strict';
/*
 * Glide physics reference implementation.
 *
 * This is a line-for-line companion to Sources/GlideCore/{Curves,Physics}.
 * It exists because the Swift cannot be executed on CI-less machines, while
 * the math absolutely must be right: every constant shipped in
 * ScrollPreset.swift is produced and range-checked by this file.
 *
 * Keep this in sync with the Swift. spec.js asserts the invariants.
 */

// ---------------------------------------------------------------------------
// Unit cubic Bezier, CSS `cubic-bezier(x1, y1, x2, y2)` semantics.
// P0 = (0,0), P3 = (1,1) are implied.
// ---------------------------------------------------------------------------

class UnitBezier {
  constructor(x1, y1, x2, y2) {
    // Polynomial coefficients, derived once. B(t) = ((a*t + b)*t + c)*t
    this.cx = 3.0 * x1;
    this.bx = 3.0 * (x2 - x1) - this.cx;
    this.ax = 1.0 - this.cx - this.bx;

    this.cy = 3.0 * y1;
    this.by = 3.0 * (y2 - y1) - this.cy;
    this.ay = 1.0 - this.cy - this.by;

    this.controls = [x1, y1, x2, y2];
  }

  sampleX(t) { return ((this.ax * t + this.bx) * t + this.cx) * t; }
  sampleY(t) { return ((this.ay * t + this.by) * t + this.cy) * t; }
  sampleDerivativeX(t) { return (3.0 * this.ax * t + 2.0 * this.bx) * t + this.cx; }

  /*
   * Invert x = B_x(t) for t. Newton-Raphson first (quadratic convergence,
   * usually 3-4 iterations), then bisection as a guaranteed-progress
   * fallback for the flat regions where the derivative collapses toward 0
   * and Newton would either stall or shoot outside [0,1].
   */
  solveT(x, epsilon = 1e-9) {
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;

    let t = x; // x is a good initial guess for a near-diagonal curve
    for (let i = 0; i < 8; i++) {
      const error = this.sampleX(t) - x;
      if (Math.abs(error) < epsilon) return t;
      const d = this.sampleDerivativeX(t);
      if (Math.abs(d) < 1e-6) break; // derivative too flat; hand over to bisection
      t -= error / d;
    }

    /*
     * Bisection. We converge the *bracket* rather than returning as soon as
     * x lands within epsilon: on curves whose derivative collapses mid-range
     * (cubic-bezier(1,0,0,1) is flat at t=0.5) a satisfied x-tolerance still
     * leaves t wrong in the 5th decimal, because inverting a near-constant
     * function is ill-conditioned. 60 halvings costs nothing once per frame
     * and pins t as tightly as a double allows.
     */
    let lo = 0.0, hi = 1.0;
    t = x;
    for (let i = 0; i < 60 && (hi - lo) > 1e-15; i++) {
      const sampled = this.sampleX(t);
      if (x > sampled) lo = t; else hi = t;
      t = (hi + lo) * 0.5;
    }
    return t;
  }

  /* The actual easing function: given progress 0..1, return eased 0..1. */
  evaluate(x, epsilon = 1e-9) { return this.sampleY(this.solveT(x, epsilon)); }
}

// ---------------------------------------------------------------------------
// Acceleration curve: input wheel speed (ticks/sec) -> pixels per tick.
//
// Slow, deliberate scrolling should move a small, predictable amount so you
// can land on a line. Fast spinning should cover ground. The shape between
// those two anchors is what makes a mouse feel cheap or expensive, so it is
// a tunable Bezier rather than a hardcoded exponent.
// ---------------------------------------------------------------------------

class AccelerationCurve {
  constructor({ minSpeed, maxSpeed, minDistance, maxDistance, bezier }) {
    this.minSpeed = minSpeed;
    this.maxSpeed = maxSpeed;
    this.minDistance = minDistance;
    this.maxDistance = maxDistance;
    this.bezier = bezier;
  }

  /* pixels to travel for one wheel tick arriving at `speed` ticks/sec */
  distance(speed) {
    const span = this.maxSpeed - this.minSpeed;
    const raw = span <= 0 ? 0 : (speed - this.minSpeed) / span;
    const clamped = Math.min(1, Math.max(0, raw));
    const eased = this.bezier.evaluate(clamped);
    return this.minDistance + eased * (this.maxDistance - this.minDistance);
  }
}

// ---------------------------------------------------------------------------
// Momentum / friction.
//
// v(t) = v0 * e^(-k t)  =>  total distance travelled is exactly v0 / k.
// Choosing an analytically integrable model (rather than a per-frame
// multiply pulled out of thin air) means the UI can promise "this fling
// travels N pixels" before the first frame is drawn.
// ---------------------------------------------------------------------------

class MomentumScroll {
  constructor({ friction, stopThreshold = 1.0 }) {
    this.k = friction;
    this.stopThreshold = stopThreshold;
  }

  /* Exact closed-form total travel for an initial velocity, in pixels. */
  projectedDistance(v0) { return v0 / this.k; }

  /* Exact time until |v| decays below the stop threshold, in seconds. */
  projectedDuration(v0) {
    const v = Math.abs(v0);
    if (v <= this.stopThreshold) return 0;
    return Math.log(v / this.stopThreshold) / this.k;
  }

  /*
   * Advance one display-link frame. Returns the pixel delta to emit.
   *
   * The integral of an exponential over a frame is itself closed-form:
   *
   *     dx = integral(0..dt) v*e^(-k t) dt = (v - v') / k
   *
   * so we take that directly instead of approximating with a trapezoid. It
   * is exact at any frame rate (a dropped frame or a 30Hz display costs no
   * accuracy), it is cheaper than the trapezoid, and it guarantees the sum
   * of the deltas can never exceed the advertised projectedDistance — which
   * a trapezoid, over-estimating a convex curve, does.
   */
  step(v, dt) {
    const vNext = v * Math.exp(-this.k * dt);
    return { velocity: vNext, delta: (v - vNext) / this.k };
  }

  /*
   * Launch velocity needed to travel exactly `distance` points.
   * Inverse of projectedDistance, and the key to the whole engine: it lets a
   * wheel tick that "should move 48 points" be expressed as an impulse, so
   * momentum and discrete stepping become one mechanism.
   */
  velocityToTravel(distance) { return distance * this.k; }

  /* Frame-by-frame integration, as the display link will actually run it. */
  simulate(v0, dt, maxFrames = 100000) {
    let v = v0;
    let x = 0;
    const frames = [];
    for (let i = 0; i < maxFrames; i++) {
      if (Math.abs(v) < this.stopThreshold) break;
      const s = this.step(v, dt);
      x += s.delta;
      v = s.velocity;
      frames.push({ t: (i + 1) * dt, v, x });
    }
    return { distance: x, frames, finalVelocity: v };
  }
}

// ---------------------------------------------------------------------------
// Rubber band, matching the feel of AppKit overscroll.
//
// d = (1 - 1/(c * x / L + 1)) * L
//
// Asymptotically approaches L no matter how hard you pull, and the reciprocal
// gives the characteristic "getting stiffer" resistance.
// ---------------------------------------------------------------------------

function rubberBand(offset, limit, coefficient = 0.55) {
  if (limit <= 0) return 0;
  const sign = offset < 0 ? -1 : 1;
  const x = Math.abs(offset);
  return sign * (1.0 - 1.0 / ((coefficient * x / limit) + 1.0)) * limit;
}

// ---------------------------------------------------------------------------
// Free-spin detection.
//
// A flick of the wheel and a careful two-line nudge arrive through the same
// API; the only difference is the tick cadence. We keep a short rolling
// window of inter-tick intervals and call it a free spin once the cadence
// stays above a threshold for a minimum number of consecutive ticks.
// ---------------------------------------------------------------------------

class FreeSpinDetector {
  constructor({ speedThreshold = 14.0, requiredTicks = 3, windowSize = 5, resetInterval = 0.25 }) {
    this.speedThreshold = speedThreshold;
    this.requiredTicks = requiredTicks;
    this.windowSize = windowSize;
    this.resetInterval = resetInterval;
    this.intervals = [];
    this.lastTimestamp = null;
    this.consecutiveFast = 0;
    this.active = false;
  }

  /* Returns true when the current tick is part of a free spin. */
  push(timestamp, direction) {
    if (this.lastTimestamp !== null) {
      const gap = timestamp - this.lastTimestamp;
      if (gap > this.resetInterval) this.reset(); else {
        this.intervals.push(gap);
        if (this.intervals.length > this.windowSize) this.intervals.shift();
      }
    }
    this.lastTimestamp = timestamp;

    const speed = this.speed();
    if (speed >= this.speedThreshold) {
      this.consecutiveFast += 1;
    } else {
      this.consecutiveFast = 0;
    }
    this.active = this.consecutiveFast >= this.requiredTicks;
    return this.active;
  }

  /* Smoothed ticks/second across the rolling window. */
  speed() {
    if (this.intervals.length === 0) return 0;
    const mean = this.intervals.reduce((a, b) => a + b, 0) / this.intervals.length;
    return mean <= 0 ? 0 : 1.0 / mean;
  }

  reset() {
    this.intervals = [];
    this.consecutiveFast = 0;
    this.active = false;
  }
}

module.exports = { UnitBezier, AccelerationCurve, MomentumScroll, rubberBand, FreeSpinDetector };

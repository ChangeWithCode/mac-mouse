'use strict';
/* Faithful port of Sources/GlideCore/Physics/ScrollEngine.swift. */
const { AccelerationCurve, UnitBezier, MomentumScroll, FreeSpinDetector } = require('./physics');

const Phase = { none: 0, began: 1, stationary: 2, changed: 4, ended: 8, cancelled: 16, mayBegin: 32 };
const Momentum = { none: 0, begin: 1, continue: 2, end: 3 };

class ScrollEngine {
  constructor(preset) {
    this.preset = preset;
    this.flickBoost = 1.6;
    this.inverted = false;
    this.inputTimeout = 0.09;

    this.state = 'idle';
    this.velocity = 0;
    this.remainder = 0;
    this.lastTickTime = 0;
    this.lastFrameTime = null;
    this.streamHasOpened = false;   // first frame of the CURRENT stream emitted?
    this.gestureIsOpen = false;     // began sent, ended not yet
    this.needsMomentumEnd = false;
    this.detector = new FreeSpinDetector({});
  }

  get momentum() {
    return new MomentumScroll({ friction: this.preset.friction, stopThreshold: this.preset.stopThreshold });
  }

  ingest(direction, timestamp) {
    if (direction === 0) return;
    const sign = direction < 0 ? -1 : 1;
    const dir = this.inverted ? -sign : sign;

    this.detector.push(timestamp, dir);

    if (this.velocity !== 0 && (this.velocity < 0) !== (dir < 0)) {
      this.velocity = 0;
      this.remainder = 0;
    }

    let distance = this.preset.acceleration.distance(this.detector.speed());
    if (this.detector.active) distance *= this.flickBoost;
    this.velocity += this.momentum.velocityToTravel(distance) * dir;

    this.lastTickTime = timestamp;
    if (this.state !== 'tracking') {
      // Resuming out of a coast: that gesture was already closed with `ended`,
      // so the momentum stream has to be closed and a NEW gesture opened.
      // Resuming out of `settling` is different — the gesture is still open, so
      // it simply carries on as `changed`.
      if (this.state === 'coasting') {
        this.needsMomentumEnd = true;
        this.streamHasOpened = false;
      }
      if (this.state === 'idle') { this.lastFrameTime = null; }
      this.state = 'tracking';
    }
  }

  advance(now) {
    if (this.state === 'idle') return null;

    if (this.needsMomentumEnd) {
      this.needsMomentumEnd = false;
      this.lastFrameTime = now;
      return { delta: 0, phase: Phase.none, momentumPhase: Momentum.end, isFinal: false };
    }

    const dt = this.lastFrameTime === null ? 0 : Math.max(0, Math.min(now - this.lastFrameTime, 0.1));
    this.lastFrameTime = now;
    const mom = this.momentum;

    // Input has gone quiet: decide how this gesture ends.
    if (this.state === 'tracking' && (now - this.lastTickTime) > this.inputTimeout) {
      this.detector.reset();
      if (this.preset.momentumEnabled && Math.abs(this.velocity) >= mom.stopThreshold) {
        this.state = 'coasting';
        this.streamHasOpened = false;  // the momentum stream opens fresh
        this.gestureIsOpen = false;
        return { delta: 0, phase: Phase.ended, momentumPhase: Momentum.none, isFinal: false };
      }
      // No momentum stream — but the notch still owes distance. Let it decay
      // out naturally as part of the open gesture instead of truncating it.
      this.state = 'settling';
    }

    const stepped = mom.step(this.velocity, dt);
    this.velocity = stepped.velocity;
    this.remainder += stepped.delta;
    const whole = Math.trunc(this.remainder);
    this.remainder -= whole;
    const delta = whole;

    const stopped = Math.abs(this.velocity) < mom.stopThreshold;
    if (stopped && (this.state === 'coasting' || this.state === 'settling')) {
      return this.finish(delta);
    }
    if (delta === 0 && this.streamHasOpened) return null;

    let phase, momentumPhase;
    if (this.state === 'coasting') {
      phase = Phase.none;
      momentumPhase = this.streamHasOpened ? Momentum.continue : Momentum.begin;
    } else {
      phase = this.gestureIsOpen ? Phase.changed : Phase.began;
      momentumPhase = Momentum.none;
      this.gestureIsOpen = true;
    }
    this.streamHasOpened = true;
    return { delta, phase, momentumPhase, isFinal: false };
  }

  finish(trailingDelta = 0) {
    const wasCoasting = this.state === 'coasting';
    const hadOpenGesture = this.gestureIsOpen;
    this.state = 'idle';
    this.velocity = 0;
    this.remainder = 0;
    this.lastFrameTime = null;
    this.streamHasOpened = false;
    this.gestureIsOpen = false;
    this.needsMomentumEnd = false;
    this.detector.reset();
    return {
      // `ended` must carry no motion or the view double-counts it; a momentum
      // `end` is not the gesture boundary, so it may carry the last fragment.
      delta: wasCoasting ? trailingDelta : 0,
      phase: wasCoasting ? Phase.none : (hadOpenGesture ? Phase.ended : Phase.none),
      momentumPhase: wasCoasting ? Momentum.end : Momentum.none,
      isFinal: true,
    };
  }
}

/* Drives an engine through a scripted tick sequence at a fixed frame rate. */
function run(engine, ticks, { fps = 60, maxSeconds = 12 } = {}) {
  const dt = 1 / fps;
  const frames = [];
  const queue = [...ticks];
  let t = 0;
  // Prime: deliver the first tick before the first frame.
  while (t < maxSeconds) {
    while (queue.length && queue[0].at <= t) {
      const tick = queue.shift();
      engine.ingest(tick.dir, tick.at);
    }
    const f = engine.advance(t);
    if (f) frames.push({ ...f, t });
    if (!queue.length && engine.state === 'idle') break;
    t += dt;
  }
  return frames;
}

module.exports = { ScrollEngine, Phase, Momentum, run };

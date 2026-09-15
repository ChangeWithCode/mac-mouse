'use strict';
/* Executable spec for the Glide physics core. Run: node spec.js */

const { UnitBezier, AccelerationCurve, MomentumScroll, rubberBand, FreeSpinDetector } = require('./physics');

let passed = 0, failed = 0;
const failures = [];

function check(name, fn) {
  try { fn(); passed++; console.log(`  \x1b[32m✓\x1b[0m ${name}`); }
  catch (e) { failed++; failures.push(`${name}: ${e.message}`); console.log(`  \x1b[31m✗\x1b[0m ${name}\n      ${e.message}`); }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function close(a, b, tol, msg) {
  if (!(Math.abs(a - b) <= tol)) throw new Error(`${msg} (got ${a}, want ${b} ±${tol})`);
}
function section(t) { console.log(`\n\x1b[1m${t}\x1b[0m`); }

// --------------------------------------------------------------------------
section('UnitBezier');

const curves = [
  [0.25, 0.1, 0.25, 1.0],   // CSS "ease"
  [0.42, 0.0, 1.0, 1.0],    // ease-in
  [0.0, 0.0, 0.58, 1.0],    // ease-out
  [0.42, 0.0, 0.58, 1.0],   // ease-in-out
  [0.0, 0.0, 1.0, 1.0],     // linear
  [1.0, 0.0, 0.0, 1.0],     // extreme S — derivative collapses at both ends
  [0.0, 0.9, 1.0, 0.1],     // inverted S
];

check('evaluate pins the endpoints exactly', () => {
  for (const c of curves) {
    const b = new UnitBezier(...c);
    close(b.evaluate(0), 0, 1e-12, `f(0) for ${c}`);
    close(b.evaluate(1), 1, 1e-12, `f(1) for ${c}`);
  }
});

check('solveT inverts sampleX to 1e-8 in x across all curves', () => {
  // The contract that matters: feeding solveT's answer back through sampleX
  // must reproduce the input. This is well-conditioned for every curve.
  for (const c of curves) {
    const b = new UnitBezier(...c);
    for (let i = 0; i <= 200; i++) {
      const x = i / 200;
      close(b.sampleX(b.solveT(x)), x, 1e-8, `x-roundtrip x=${x} on ${c}`);
    }
  }
});

check('solveT recovers t itself wherever the curve is not degenerate', () => {
  // Recovering t is ill-conditioned where dx/dt collapses — cubic-bezier(1,0,0,1)
  // is exactly flat at t=0.5, so a perfect x is still a soft t there. Assert the
  // tight bound only where the derivative carries real information.
  for (const c of curves) {
    const b = new UnitBezier(...c);
    for (let i = 0; i <= 200; i++) {
      const t = i / 200;
      if (Math.abs(b.sampleDerivativeX(t)) < 0.05) continue;
      close(b.solveT(b.sampleX(t)), t, 1e-6, `t-roundtrip t=${t} on ${c}`);
    }
  }
});

check('solveT never returns NaN or escapes [0,1]', () => {
  for (const c of curves) {
    const b = new UnitBezier(...c);
    for (let i = -10; i <= 210; i++) {
      const x = i / 200;
      const t = b.solveT(x);
      assert(Number.isFinite(t), `NaN/Inf at x=${x} on ${c}`);
      assert(t >= 0 && t <= 1, `t=${t} out of range at x=${x} on ${c}`);
    }
  }
});

check('output is monotonically non-decreasing for in-range controls', () => {
  for (const c of curves.slice(0, 6)) {
    const b = new UnitBezier(...c);
    let prev = -Infinity;
    for (let i = 0; i <= 500; i++) {
      const y = b.evaluate(i / 500);
      assert(y >= prev - 1e-9, `non-monotonic at x=${i / 500} on ${c}: ${y} < ${prev}`);
      prev = y;
    }
  }
});

check('the extreme S-curve still converges (bisection fallback engages)', () => {
  const b = new UnitBezier(1.0, 0.0, 0.0, 1.0);
  for (let i = 0; i <= 100; i++) {
    const x = i / 100;
    const y = b.evaluate(x);
    assert(Number.isFinite(y) && y >= -1e-9 && y <= 1 + 1e-9, `bad y=${y} at x=${x}`);
  }
  // Symmetric curve: f(0.5) must sit at 0.5.
  close(b.evaluate(0.5), 0.5, 1e-6, 'midpoint of symmetric S');
});

// --------------------------------------------------------------------------
section('AccelerationCurve');

const standard = new AccelerationCurve({
  minSpeed: 1.0, maxSpeed: 28.0,
  minDistance: 48.0, maxDistance: 220.0,
  bezier: new UnitBezier(0.35, 0.0, 0.65, 1.0),
});

check('clamps below minSpeed and above maxSpeed', () => {
  close(standard.distance(0), 48.0, 1e-9, 'below range');
  close(standard.distance(-50), 48.0, 1e-9, 'negative speed');
  close(standard.distance(28), 220.0, 1e-9, 'at maxSpeed');
  close(standard.distance(1000), 220.0, 1e-9, 'above range');
});

check('is monotonically non-decreasing in input speed', () => {
  let prev = -Infinity;
  for (let s = -5; s <= 60; s += 0.05) {
    const d = standard.distance(s);
    assert(d >= prev - 1e-9, `non-monotonic at speed ${s}: ${d} < ${prev}`);
    prev = d;
  }
});

check('every output stays inside [minDistance, maxDistance]', () => {
  for (let s = -5; s <= 60; s += 0.05) {
    const d = standard.distance(s);
    assert(d >= 48.0 - 1e-9 && d <= 220.0 + 1e-9, `d=${d} out of bounds at speed ${s}`);
  }
});

check('a degenerate zero-width speed range does not divide by zero', () => {
  const degenerate = new AccelerationCurve({
    minSpeed: 5, maxSpeed: 5, minDistance: 10, maxDistance: 99,
    bezier: new UnitBezier(0.25, 0.1, 0.25, 1.0),
  });
  const d = degenerate.distance(5);
  assert(Number.isFinite(d), `got ${d}`);
});

// --------------------------------------------------------------------------
section('MomentumScroll');

const momentum = new MomentumScroll({ friction: 5.2, stopThreshold: 1.0 });

check('discrete integration matches the closed form at 60fps', () => {
  for (const v0 of [200, 900, 2400, 6000]) {
    const sim = momentum.simulate(v0, 1 / 60);
    // x(t) = (v0 - v(t)) / k exactly, for any t.
    const exact = (v0 - sim.finalVelocity) / 5.2;
    const errorPx = Math.abs(sim.distance - exact);
    assert(errorPx < 1e-9, `v0=${v0}: drifted ${errorPx.toExponential(3)}px from closed form`);
  }
});

check('discrete integration still tracks the closed form at 30fps', () => {
  for (const v0 of [200, 2400, 6000]) {
    const sim = momentum.simulate(v0, 1 / 30);
    const exact = (v0 - sim.finalVelocity) / 5.2;
    assert(Math.abs(sim.distance - exact) < 1e-9, `v0=${v0} drifted at 30fps`);
  }
});

check('velocity decreases strictly and the fling terminates', () => {
  const sim = momentum.simulate(4000, 1 / 60);
  assert(sim.frames.length > 0, 'no frames produced');
  assert(sim.frames.length < 2000, `fling ran ${sim.frames.length} frames — not terminating`);
  for (let i = 1; i < sim.frames.length; i++) {
    assert(sim.frames[i].v < sim.frames[i - 1].v, `velocity rose at frame ${i}`);
  }
  assert(Math.abs(sim.finalVelocity) < 1.0, 'stopped above the threshold');
});

check('projectedDuration agrees with the simulated frame count', () => {
  for (const v0 of [500, 3000]) {
    const predicted = momentum.projectedDuration(v0);
    const sim = momentum.simulate(v0, 1 / 60);
    const actual = sim.frames.length / 60;
    close(actual, predicted, 1 / 30, `duration for v0=${v0}`);
  }
});

check('projectedDistance bounds every simulated fling', () => {
  for (const v0 of [100, 1000, 8000]) {
    const sim = momentum.simulate(v0, 1 / 60);
    assert(sim.distance <= momentum.projectedDistance(v0) + 1e-6,
      `v0=${v0}: travelled ${sim.distance} > bound ${momentum.projectedDistance(v0)}`);
  }
});

check('a sub-threshold flick produces no motion at all', () => {
  const sim = momentum.simulate(0.4, 1 / 60);
  assert(sim.frames.length === 0 && sim.distance === 0, 'moved when it should not have');
});

// --------------------------------------------------------------------------
section('rubberBand');

check('is zero at zero and odd-symmetric', () => {
  close(rubberBand(0, 500), 0, 1e-12, 'at origin');
  for (const x of [10, 250, 900]) {
    close(rubberBand(-x, 500), -rubberBand(x, 500), 1e-12, `symmetry at ${x}`);
  }
});

check('never exceeds the limit no matter how hard it is pulled', () => {
  for (const x of [100, 1000, 100000, 1e9]) {
    assert(Math.abs(rubberBand(x, 500)) < 500, `escaped the limit at pull=${x}`);
  }
});

check('resists progressively — gain always shrinks', () => {
  let prevGain = Infinity;
  for (let x = 1; x < 2000; x += 1) {
    const gain = rubberBand(x, 500) / x;
    assert(gain <= prevGain + 1e-12, `resistance loosened at ${x}`);
    prevGain = gain;
  }
});

check('a zero-size limit degrades to no movement', () => {
  close(rubberBand(300, 0), 0, 1e-12, 'zero limit');
});

// --------------------------------------------------------------------------
section('FreeSpinDetector');

check('deliberate slow ticks never register as a free spin', () => {
  const d = new FreeSpinDetector({});
  let t = 0;
  for (let i = 0; i < 20; i++) { t += 0.18; assert(!d.push(t, 1), `tripped on tick ${i}`); }
});

check('a fast spin engages, but not before requiredTicks', () => {
  const d = new FreeSpinDetector({ speedThreshold: 14, requiredTicks: 3 });
  let t = 0, firstActive = -1;
  for (let i = 0; i < 12; i++) {
    t += 1 / 40; // 40 ticks/sec
    if (d.push(t, 1) && firstActive < 0) firstActive = i;
  }
  assert(firstActive >= 3, `engaged too eagerly at tick ${firstActive}`);
  assert(firstActive <= 6, `never engaged (or far too late): ${firstActive}`);
});

check('a pause resets the spin state', () => {
  const d = new FreeSpinDetector({ speedThreshold: 14, requiredTicks: 3 });
  let t = 0;
  for (let i = 0; i < 12; i++) { t += 1 / 40; d.push(t, 1); }
  assert(d.active, 'precondition: should be spinning');
  t += 1.0; // let go of the wheel
  d.push(t, 1);
  assert(!d.active, 'stayed active across a one-second pause');
});

check('reported speed tracks a steady cadence', () => {
  const d = new FreeSpinDetector({});
  let t = 0;
  for (let i = 0; i < 10; i++) { t += 1 / 25; d.push(t, 1); }
  close(d.speed(), 25, 0.5, 'smoothed cadence');
});

// --------------------------------------------------------------------------
console.log(`\n\x1b[1m${passed} passed, ${failed} failed\x1b[0m`);
if (failed) { console.log('\nFailures:'); failures.forEach(f => console.log('  - ' + f)); process.exit(1); }

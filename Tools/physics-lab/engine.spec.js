'use strict';
const { UnitBezier, AccelerationCurve } = require('./physics');
const { ScrollEngine, Phase, Momentum, run } = require('./engine');

let passed = 0, failed = 0; const failures = [];
function check(n, fn) { try { fn(); passed++; console.log(`  \x1b[32m✓\x1b[0m ${n}`); } catch (e) { failed++; failures.push(`${n}: ${e.message}`); console.log(`  \x1b[31m✗\x1b[0m ${n}\n      ${e.message}`); } }
function assert(c, m) { if (!c) throw new Error(m); }

const balanced = {
  acceleration: new AccelerationCurve({ minSpeed: 1, maxSpeed: 28, minDistance: 48, maxDistance: 220, bezier: new UnitBezier(0.35, 0, 0.65, 1) }),
  friction: 6.4, stopThreshold: 8, momentumEnabled: true,
};
const snappy = {
  acceleration: new AccelerationCurve({ minSpeed: 1, maxSpeed: 26, minDistance: 52, maxDistance: 190, bezier: new UnitBezier(0.42, 0, 0.58, 1) }),
  friction: 22, stopThreshold: 12, momentumEnabled: false,
};

const phaseName = p => Object.keys(Phase).find(k => Phase[k] === p);
const momName = p => Object.keys(Momentum).find(k => Momentum[k] === p);
const trace = frames => frames.map(f => `${phaseName(f.phase)}/${momName(f.momentumPhase)}`).join(' ');

/* A gesture is well-formed if a view could actually follow it. */
function assertWellFormed(frames, { expectMomentum }) {
  assert(frames.length > 0, 'no frames at all');
  let open = false, inMomentum = false, sawEnded = false;
  for (const [i, f] of frames.entries()) {
    if (f.phase === Phase.began) {
      assert(!open, `began while a gesture was already open (frame ${i}): ${trace(frames)}`);
      assert(!inMomentum, `began during momentum without closing it (frame ${i}): ${trace(frames)}`);
      open = true; sawEnded = false;
    } else if (f.phase === Phase.changed) {
      assert(open, `changed with no open gesture (frame ${i}): ${trace(frames)}`);
    } else if (f.phase === Phase.ended) {
      assert(open, `ended with no open gesture (frame ${i}): ${trace(frames)}`);
      assert(f.delta === 0, `ended carried a delta of ${f.delta} — the view would double-count it`);
      open = false; sawEnded = true;
    }
    if (f.momentumPhase === Momentum.begin) {
      assert(!open, `momentum began while the gesture was still open (frame ${i}): ${trace(frames)}`);
      assert(sawEnded, `momentum began without a preceding ended (frame ${i}): ${trace(frames)}`);
      assert(!inMomentum, `momentum began twice (frame ${i}): ${trace(frames)}`);
      inMomentum = true;
    } else if (f.momentumPhase === Momentum.continue) {
      assert(inMomentum, `momentum continued with no momentum in flight (frame ${i}): ${trace(frames)}`);
    } else if (f.momentumPhase === Momentum.end) {
      assert(inMomentum, `momentum ended with none in flight (frame ${i}): ${trace(frames)}`);
      inMomentum = false;
    }
  }
  assert(!open, `gesture never closed: ${trace(frames)}`);
  assert(!inMomentum, `momentum never closed: ${trace(frames)}`);
  if (expectMomentum !== undefined) {
    const had = frames.some(f => f.momentumPhase === Momentum.begin);
    assert(had === expectMomentum, `expected momentum=${expectMomentum}, got ${had}: ${trace(frames)}`);
  }
  assert(frames[frames.length - 1].isFinal, 'the last frame must be the final one');
}

console.log('\n\x1b[1mScrollEngine\x1b[0m');

check('an idle engine emits nothing', () => {
  const e = new ScrollEngine(balanced);
  for (let i = 0; i < 10; i++) assert(e.advance(i / 60) === null, 'emitted while idle');
});

check('a single tick produces a well-formed gesture with momentum', () => {
  const e = new ScrollEngine(balanced);
  const frames = run(e, [{ at: 0, dir: 1 }]);
  assertWellFormed(frames, { expectMomentum: true });
});

check('a slow scroll conserves distance to within a point per tick', () => {
  const e = new ScrollEngine(balanced);
  e.flickBoost = 1.0; // isolate the curve from the flick boost
  const ticks = [];
  for (let i = 0; i < 10; i++) ticks.push({ at: 0.2 * i, dir: 1 });
  const frames = run(e, ticks, { maxSeconds: 20 });
  const total = frames.reduce((a, f) => a + f.delta, 0);
  // Cadence is 5/s once established; the first tick has no measurable cadence
  // and falls back to minDistance.
  const expected = balanced.acceleration.distance(0) + 9 * balanced.acceleration.distance(5);
  assert(Math.abs(total - expected) < 10,
    `scrolled ${total}pt, curve promised ${expected.toFixed(1)}pt`);
});

check('distance is conserved regardless of frame rate', () => {
  const totals = [30, 60, 120, 144].map(fps => {
    const e = new ScrollEngine(balanced); e.flickBoost = 1.0;
    const ticks = []; for (let i = 0; i < 8; i++) ticks.push({ at: 0.15 * i, dir: 1 });
    return run(e, ticks, { fps, maxSeconds: 20 }).reduce((a, f) => a + f.delta, 0);
  });
  const spread = Math.max(...totals) - Math.min(...totals);
  assert(spread <= 2, `frame rate changed the distance by ${spread}pt: ${totals.join(', ')}`);
});

check('resuming mid-coast opens a new gesture instead of orphaning the old one', () => {
  const e = new ScrollEngine(balanced);
  // Scroll, let go so it coasts, then grab it again while it is still moving.
  const frames = run(e, [
    { at: 0.00, dir: 1 }, { at: 0.05, dir: 1 }, { at: 0.10, dir: 1 },
    { at: 0.60, dir: 1 }, { at: 0.65, dir: 1 },
  ], { maxSeconds: 20 });
  assertWellFormed(frames, {});
  const begans = frames.filter(f => f.phase === Phase.began).length;
  assert(begans === 2, `expected two gestures, saw ${begans}: ${trace(frames)}`);
});

check('reversing direction cancels the fling rather than fighting it', () => {
  const e = new ScrollEngine(balanced);
  const down = run(new ScrollEngine(balanced), [{ at: 0, dir: 1 }, { at: 0.05, dir: 1 }], { maxSeconds: 20 });
  const downTotal = down.reduce((a, f) => a + f.delta, 0);

  const frames = run(e, [
    { at: 0.00, dir: 1 }, { at: 0.05, dir: 1 },
    { at: 0.12, dir: -1 }, { at: 0.17, dir: -1 },
  ], { maxSeconds: 20 });
  const net = frames.reduce((a, f) => a + f.delta, 0);
  assert(net < downTotal, `reversal did not take effect (net ${net} vs ${downTotal})`);
  assert(frames.some(f => f.delta < 0), 'never actually scrolled back');
});

check('momentum-disabled presets never emit a momentum phase', () => {
  const e = new ScrollEngine(snappy);
  const frames = run(e, [{ at: 0, dir: 1 }, { at: 0.05, dir: 1 }], { maxSeconds: 10 });
  assertWellFormed(frames, { expectMomentum: false });
});

check('a momentum-disabled preset settles quickly', () => {
  const e = new ScrollEngine(snappy);
  const frames = run(e, [{ at: 0, dir: 1 }], { maxSeconds: 10 });
  const last = frames[frames.length - 1].t;
  assert(last < 0.5, `took ${last.toFixed(2)}s to settle`);
});

check('the ended frame never carries motion', () => {
  const e = new ScrollEngine(balanced);
  const frames = run(e, [{ at: 0, dir: 1 }, { at: 0.04, dir: 1 }, { at: 0.08, dir: 1 }], { maxSeconds: 20 });
  for (const f of frames) if (f.phase === Phase.ended) assert(f.delta === 0, `ended carried ${f.delta}`);
});

check('sub-point remainders are carried, not truncated away', () => {
  // Line-by-line at a slow cadence: 40pt per tick, 20 ticks, no acceleration.
  const lineByLine = {
    acceleration: new AccelerationCurve({ minSpeed: 1, maxSpeed: 40, minDistance: 40, maxDistance: 40, bezier: new UnitBezier(0, 0, 1, 1) }),
    friction: 30, stopThreshold: 12, momentumEnabled: false,
  };
  const e = new ScrollEngine(lineByLine); e.flickBoost = 1.0;
  const ticks = []; for (let i = 0; i < 20; i++) ticks.push({ at: 0.25 * i, dir: 1 });
  const total = run(e, ticks, { fps: 120, maxSeconds: 30 }).reduce((a, f) => a + f.delta, 0);
  // 20 ticks x 40pt = 800. Truncation would bleed a fraction of a point every
  // frame and land well short.
  assert(Math.abs(total - 800) <= 20, `expected ~800pt, got ${total}pt`);
});

check('inverted mode mirrors the output exactly', () => {
  const a = new ScrollEngine(balanced);
  const b = new ScrollEngine(balanced); b.inverted = true;
  const ticks = [{ at: 0, dir: 1 }, { at: 0.05, dir: 1 }];
  const ta = run(a, ticks, { maxSeconds: 20 }).reduce((s, f) => s + f.delta, 0);
  const tb = run(b, ticks, { maxSeconds: 20 }).reduce((s, f) => s + f.delta, 0);
  assert(ta === -tb, `expected mirrored totals, got ${ta} and ${tb}`);
});

check('a long spin stays well-formed and terminates', () => {
  const e = new ScrollEngine(balanced);
  const ticks = []; for (let i = 0; i < 60; i++) ticks.push({ at: i / 45, dir: 1 });
  const frames = run(e, ticks, { maxSeconds: 30 });
  assertWellFormed(frames, { expectMomentum: true });
});

console.log(`\n\x1b[1m${passed} passed, ${failed} failed\x1b[0m`);
if (failed) { console.log('\nFailures:'); failures.forEach(f => console.log('  - ' + f)); process.exit(1); }

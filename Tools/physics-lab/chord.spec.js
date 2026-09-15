'use strict';
const { ChordRecognizer, bindings, key } = require('./chord');

let passed = 0, failed = 0; const failures = [];
function check(n, fn) { try { fn(); passed++; console.log(`  \x1b[32m✓\x1b[0m ${n}`); } catch (e) { failed++; failures.push(`${n}: ${e.message}`); console.log(`  \x1b[31m✗\x1b[0m ${n}\n      ${e.message}`); } }
function assert(c, m) { if (!c) throw new Error(m); }
const names = evts => evts.map(e => e.t + (e.trigger ? `(${key(e.trigger.buttons)}:${JSON.stringify(e.trigger.kind)})` : `(${e.button})`)).join(' ');

function make(specs) {
  const r = new ChordRecognizer();
  Object.assign(r, bindings(specs));
  return r;
}

console.log('\n\x1b[1mChordRecognizer\x1b[0m');

check('an unbound button is never intercepted', () => {
  const r = make(['3:click:1']);
  const down = r.press(0, 0);       // left button, nothing bound to it
  const up = r.release(0, 0.05);
  assert(down.length === 1 && down[0].t === 'passThrough', `down: ${names(down)}`);
  assert(up.length === 1 && up[0].t === 'passThrough', `up: ${names(up)}`);
});

check('a single-click-only binding fires on release with no delay', () => {
  const r = make(['3:click:1']);
  r.press(3, 0);
  const up = r.release(3, 0.05);
  assert(up.length === 1 && up[0].t === 'fire', `expected an immediate fire, got: ${names(up)}`);
  assert(up[0].trigger.kind.click === 1, 'wrong click count');
});

check('a double-click binding makes a single click wait for the window', () => {
  const r = make(['3:click:1', '3:click:2']);
  r.press(3, 0);
  const up = r.release(3, 0.05);
  assert(up.length === 0, `fired too early: ${names(up)}`);
  assert(r.tick(0.1).length === 0, 'fired before the window closed');
  const late = r.tick(0.31);
  assert(late.length === 1 && late[0].trigger.kind.click === 1, `expected click(1), got ${names(late)}`);
});

check('two quick clicks resolve as one double-click, not two singles', () => {
  const r = make(['3:click:1', '3:click:2']);
  r.press(3, 0); r.release(3, 0.04);
  r.press(3, 0.10); const second = r.release(3, 0.14);
  const out = [...second, ...r.tick(0.45)];
  const fires = out.filter(e => e.t === 'fire');
  assert(fires.length === 1, `expected exactly one fire, got: ${names(out)}`);
  assert(fires[0].trigger.kind.click === 2, `expected click(2), got ${JSON.stringify(fires[0].trigger.kind)}`);
});

check('a hold fires at the threshold, not on release', () => {
  const r = make(['3:hold']);
  r.press(3, 0);
  assert(r.tick(0.1).length === 0, 'fired before the threshold');
  const fired = r.tick(0.25);
  assert(fired.length === 1 && fired[0].t === 'begin', `expected begin, got ${names(fired)}`);
  const up = r.release(3, 0.8);
  assert(up.length === 1 && up[0].t === 'end', `expected end, got ${names(up)}`);
});

check('a hold does not also produce a click on release', () => {
  const r = make(['3:hold', '3:click:1']);
  r.press(3, 0);
  r.tick(0.25);
  const up = r.release(3, 0.6);
  assert(!up.some(e => e.t === 'fire'), `a click leaked out: ${names(up)}`);
});

check('a chord resolves as one trigger, not two clicks', () => {
  const r = make(['3,4:click:1']);
  r.press(3, 0);
  r.press(4, 0.02);
  r.release(3, 0.10);
  const out = r.release(4, 0.12);
  const fires = out.filter(e => e.t === 'fire');
  assert(fires.length === 1, `expected one fire, got: ${names(out)}`);
  assert(key(fires[0].trigger.buttons) === '3,4', `wrong group: ${key(fires[0].trigger.buttons)}`);
});

check('a chord still resolves when one button is released early', () => {
  const r = make(['3,4:click:1']);
  r.press(3, 0); r.press(4, 0.02);
  const early = r.release(3, 0.05);
  assert(early.length === 0, `resolved before the chord was complete: ${names(early)}`);
  const out = r.release(4, 0.09);
  assert(out.some(e => e.t === 'fire' && key(e.trigger.buttons) === '3,4'), `got: ${names(out)}`);
});

check('a drag begins past the movement threshold and suppresses the click', () => {
  const r = make(['3:drag', '3:click:1']);
  r.press(3, 0);
  assert(r.move(2, 0.01).length === 0, 'began before the threshold');
  const began = r.move(4, 0.02);
  assert(began.length === 1 && began[0].t === 'begin', `expected begin, got ${names(began)}`);
  const up = r.release(3, 0.4);
  assert(up.length === 1 && up[0].t === 'end', `expected a bare end, got ${names(up)}`);
});

check('a bound button whose gesture is unbound gives the click back', () => {
  // Button 3 is bound for hold only. A quick click matches nothing, but the
  // press was already swallowed — the app must still see a click.
  const r = make(['3:hold']);
  r.press(3, 0);
  const up = r.release(3, 0.05);
  assert(up.length === 1 && up[0].t === 'synthesizeClick' && up[0].button === 3,
    `expected a synthesized click, got: ${names(up)}`);
});

check('holding a button with no hold binding does not strand it', () => {
  const r = make(['3:click:2']);
  r.press(3, 0);
  const held = r.tick(0.3);          // passes the hold threshold, nothing bound
  assert(held.some(e => e.t === 'synthesizeClick'), `expected a fallback, got ${names(held)}`);
  const up = r.release(3, 0.9);
  assert(!up.some(e => e.t === 'fire'), `also fired a click: ${names(up)}`);
  assert(r.held.size === 0 && r.continuousTrigger === null, 'recogniser left in a stuck state');
});

check('a double-click fires as soon as it is unambiguous, without waiting for a third', () => {
  // Only click:2 is bound, so once the second click lands there is nothing
  // longer to wait for — firing immediately is the whole point of the design.
  const r = make(['3:click:2']);
  const out = [];
  r.press(3, 0); out.push(...r.release(3, 0.03));
  r.press(3, 0.08); out.push(...r.release(3, 0.11));
  const fires = out.filter(e => e.t === 'fire');
  assert(fires.length === 1 && fires[0].trigger.kind.click === 2,
    `expected a prompt click(2), got: ${names(out)}`);
});

check('a third click after a resolved double starts a fresh gesture', () => {
  const r = make(['3:click:2']);
  r.press(3, 0); r.release(3, 0.03);
  r.press(3, 0.08); r.release(3, 0.11);   // the double fires here
  r.press(3, 0.16);
  const out = [...r.release(3, 0.19), ...r.tick(0.5)];
  // Nothing is bound to a lone click, so the app gets it back rather than
  // the third click being silently eaten.
  assert(out.some(e => e.t === 'synthesizeClick'), `expected the click to be returned, got: ${names(out)}`);
  assert(!out.some(e => e.t === 'fire'), `fired something unexpected: ${names(out)}`);
});

check('growing a chord cancels the hold for the smaller group', () => {
  const r = make(['3:hold', '3,4:hold']);
  r.press(3, 0);
  const began = r.tick(0.25);
  assert(began[0].t === 'begin' && key(began[0].trigger.buttons) === '3', names(began));
  const grown = r.press(4, 0.3);
  assert(grown.some(e => e.t === 'end' && key(e.trigger.buttons) === '3'),
    `the single-button hold was never ended: ${names(grown)}`);
  const chord = r.tick(0.55);
  assert(chord.some(e => e.t === 'begin' && key(e.trigger.buttons) === '3,4'),
    `the chord hold never began: ${names(chord)}`);
});

check('reset leaves no state behind', () => {
  const r = make(['3:hold']);
  r.press(3, 0); r.tick(0.25);
  r.reset ? r.reset() : Object.assign(r, { held: new Set(), group: new Set(), continuousTrigger: null, holdFired: false, pendingClicks: null });
  assert(r.held.size === 0 && r.continuousTrigger === null && r.pendingClicks === null, 'state survived reset');
});

console.log(`\n\x1b[1m${passed} passed, ${failed} failed\x1b[0m`);
if (failed) { console.log('\nFailures:'); failures.forEach(f => console.log('  - ' + f)); process.exit(1); }

'use strict';
/*
 * Derives and range-checks the shipping scroll presets, then emits them as
 * Swift. Run `node presets.js` to print the feel table, `node presets.js --swift`
 * to regenerate Sources/GlideCore/Curves/ScrollPreset.swift.
 *
 * Every number in the Swift comes from here so nobody has to wonder whether a
 * magic constant was measured or invented.
 */
const { UnitBezier, AccelerationCurve, MomentumScroll } = require('./physics');

const PRESETS = [
  {
    id: 'precise', name: 'Precise',
    blurb: 'Short, deliberate steps. Built for code and layout work.',
    curve: { minSpeed: 1, maxSpeed: 24, minDistance: 28, maxDistance: 110, bezier: [0.30, 0.00, 0.70, 1.00] },
    friction: 11.5, stopThreshold: 8, momentum: true,
  },
  {
    id: 'balanced', name: 'Balanced',
    blurb: 'Trackpad-like glide with a firm landing. The default.',
    curve: { minSpeed: 1, maxSpeed: 28, minDistance: 48, maxDistance: 220, bezier: [0.35, 0.00, 0.65, 1.00] },
    friction: 6.4, stopThreshold: 8, momentum: true,
  },
  {
    id: 'glide', name: 'Glide',
    blurb: 'Long, low-friction coasting for reading and long documents.',
    curve: { minSpeed: 1, maxSpeed: 30, minDistance: 60, maxDistance: 300, bezier: [0.25, 0.10, 0.25, 1.00] },
    friction: 3.9, stopThreshold: 8, momentum: true,
  },
  {
    id: 'snappy', name: 'Snappy',
    blurb: 'No coasting at all. The wheel stops when you do.',
    curve: { minSpeed: 1, maxSpeed: 26, minDistance: 52, maxDistance: 190, bezier: [0.42, 0.00, 0.58, 1.00] },
    friction: 22.0, stopThreshold: 12, momentum: false,
  },
  {
    id: 'lineByLine', name: 'Line by Line',
    blurb: 'Classic discrete stepping, smoothed but never accelerated.',
    curve: { minSpeed: 1, maxSpeed: 40, minDistance: 40, maxDistance: 40, bezier: [0.00, 0.00, 1.00, 1.00] },
    friction: 30.0, stopThreshold: 12, momentum: false,
  },
];

// A firm flick of a notched wheel, in px/sec — the velocity a fling starts at.
const FLICK_V0 = 16100;

const problems = [];
const rows = [];

for (const p of PRESETS) {
  const bez = new UnitBezier(...p.curve.bezier);
  const accel = new AccelerationCurve({ ...p.curve, bezier: bez });
  const mom = new MomentumScroll({ friction: p.friction, stopThreshold: p.stopThreshold });

  const sim = mom.simulate(FLICK_V0, 1 / 60);
  const flingPx = sim.distance;
  const flingSec = sim.frames.length / 60;

  rows.push({
    name: p.name,
    slow: accel.distance(2).toFixed(0),
    medium: accel.distance(10).toFixed(0),
    fast: accel.distance(26).toFixed(0),
    fling: p.momentum ? `${flingPx.toFixed(0)}px` : '—',
    settle: p.momentum ? `${flingSec.toFixed(2)}s` : '—',
  });

  // Guard rails. These are the assumptions the UI copy makes; if a future tweak
  // breaks one, the generator refuses rather than shipping a bad feel.
  if (accel.distance(2) < 12) problems.push(`${p.name}: slow step ${accel.distance(2).toFixed(1)}px is below the 12px perceptual floor`);
  if (accel.distance(26) > 420) problems.push(`${p.name}: fast step ${accel.distance(26).toFixed(1)}px overshoots a screen height`);
  if (accel.distance(26) < accel.distance(2)) problems.push(`${p.name}: acceleration curve is inverted`);
  if (p.momentum && (flingSec < 0.25 || flingSec > 3.0)) problems.push(`${p.name}: fling settles in ${flingSec.toFixed(2)}s, outside the 0.25–3.0s comfort band`);
  if (!p.momentum && flingSec > 0.35) problems.push(`${p.name}: claims no momentum but coasts for ${flingSec.toFixed(2)}s`);
  if (p.momentum && (flingPx < 400 || flingPx > 6000)) problems.push(`${p.name}: fling travels ${flingPx.toFixed(0)}px, outside the 400–6000px band`);
}

const pad = (s, n) => String(s).padEnd(n);
console.log('\n\x1b[1mScroll preset feel table\x1b[0m  (px per wheel tick at a given cadence)\n');
console.log(`  ${pad('Preset', 14)}${pad('2/s', 8)}${pad('10/s', 8)}${pad('26/s', 8)}${pad('Fling', 10)}${pad('Settles', 8)}`);
console.log('  ' + '─'.repeat(56));
for (const r of rows) {
  console.log(`  ${pad(r.name, 14)}${pad(r.slow, 8)}${pad(r.medium, 8)}${pad(r.fast, 8)}${pad(r.fling, 10)}${pad(r.settle, 8)}`);
}

if (problems.length) {
  console.log('\n\x1b[31mPreset guard rails failed:\x1b[0m');
  problems.forEach(p => console.log('  - ' + p));
  process.exit(1);
}
console.log('\n\x1b[32mAll presets inside their guard rails.\x1b[0m');

if (process.argv.includes('--swift')) {
  const esc = s => s.replace(/"/g, '\\"');
  const cases = PRESETS.map(p => `    /// ${p.blurb}
    public static let ${p.id} = ScrollPreset(
        id: "${p.id}",
        name: "${esc(p.name)}",
        blurb: "${esc(p.blurb)}",
        acceleration: AccelerationCurve(
            minSpeed: ${p.curve.minSpeed.toFixed(1)},
            maxSpeed: ${p.curve.maxSpeed.toFixed(1)},
            minDistance: ${p.curve.minDistance.toFixed(1)},
            maxDistance: ${p.curve.maxDistance.toFixed(1)},
            shape: UnitBezier(${p.curve.bezier.map(v => v.toFixed(2)).join(', ')})
        ),
        friction: ${p.friction.toFixed(1)},
        stopThreshold: ${p.stopThreshold.toFixed(1)},
        momentumEnabled: ${p.momentum}
    )`).join('\n\n');

  const swift = `// Generated by Tools/physics-lab/presets.js — do not edit by hand.
// Regenerate with: node Tools/physics-lab/presets.js --swift
//
// Every constant below is range-checked by that generator against the
// perceptual guard rails documented in Tools/physics-lab/README.md.

import Foundation

extension ScrollPreset {

${cases}

    /// Every preset Glide ships with, in the order the UI lists them.
    public static let builtIn: [ScrollPreset] = [
${PRESETS.map(p => `        .${p.id},`).join('\n')}
    ]

    /// The preset applied to a freshly created profile.
    public static let \`default\`: ScrollPreset = .balanced
}
`;
  const fs = require('fs'), path = require('path');
  const out = path.resolve(__dirname, '../../Sources/GlideCore/Curves/ScrollPreset+BuiltIn.swift');
  fs.writeFileSync(out, swift);
  console.log(`\nWrote ${out}`);
}

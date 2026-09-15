# physics-lab

A Node mirror of `Sources/GlideCore`, and the reason the maths in this project
can be trusted.

Glide's core was written on a machine with no Swift toolchain, so the Swift
could not be executed. The parts most likely to be subtly wrong — an inverse
Bézier solve, a decay integrator, two stateful recognisers — are mirrored here
and asserted, so correctness does not depend on a compiler that was never
available.

```
physics.js        UnitBezier, AccelerationCurve, MomentumScroll, rubberBand,
                  FreeSpinDetector
engine.js         ScrollEngine — the tick-to-frame state machine
chord.js          ChordRecognizer — clicks, holds, drags, chords

spec.js           24 checks over the physics core
engine.spec.js    12 checks over the scroll state machine
chord.spec.js     15 checks over the input recogniser
presets.js        Derives the shipping presets and range-checks their feel
```

Run everything with `./Scripts/verify.sh`.

## Guard rails

`presets.js` refuses to emit a preset that falls outside these bounds, so a
future tweak cannot quietly ship a bad feel:

| Check | Bound | Why |
|---|---|---|
| Slow step | ≥ 12pt | Below this a notch is not felt as movement. |
| Fast step | ≤ 420pt | Above this a notch jumps more than a screen. |
| Curve direction | fast ≥ slow | Catches an inverted curve. |
| Fling duration | 0.25–3.0s | Shorter reads as broken, longer as unresponsive. |
| Fling distance | 400–6000pt | Keeps a flick useful without losing your place. |
| "No momentum" | coasts < 0.35s | A preset claiming no momentum must not coast. |

## Keeping it in sync

The JS and the Swift are edited together. When they disagree, the JS is the one
that has actually been executed — but it is a *port*, not the product, and it
has its own failure mode: JavaScript objects are references where Swift structs
are values. One bug in this directory was exactly that (a `Set` mutating
underneath a trigger that had captured it), and it did not exist in the Swift.
Treat a failure here as a question to ask of the Swift, not an automatic verdict.

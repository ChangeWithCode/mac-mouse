# Glide

A pointing-device utility for macOS, in the spirit of
[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix): it makes a
cheap third-party mouse behave like an Apple Trackpad — smooth pixel-precise
scrolling with momentum and rubber-band bounce, button remapping, and
trackpad-style gestures on a held button.

Glide adds the four things Mac Mouse Fix is most often asked for:

| | |
|---|---|
| **Layered profiles** | Settings stack — global, then per-device, then per-app, then a modal layer — with each layer overriding only what it actually sets. |
| **Per-device settings** | Each mouse is identified from its HID properties and keeps its own settings across reboots, ports and Bluetooth re-pairs. |
| **Chords and macros** | Any buttons held together form a chord. Bind one to a keystroke, a recorded macro, or a shell command. |
| **A tunable curve** | The acceleration curve is a Bézier you drag, with the effect shown live against your actual wheel cadence. |

---

## Status — read this first

**This code has never been compiled.** It was written on a Linux machine with
no Swift toolchain and no Xcode, and the egress proxy blocked installing one.
Expect to fix compile errors on the first build.

What that means in practice:

- **The maths and the state machines are tested and correct.** They are mirrored
  by a Node harness in [`Tools/physics-lab/`](Tools/physics-lab/) that asserts
  the same invariants, and all 39 checks pass. That harness caught four real
  bugs, described below.
- **The Swift has not been type-checked.** Expect missing imports, API drift and
  signature mistakes — the ordinary first-build noise.
- **The macOS integration is unverified.** `CGEventTap`, `IOHIDManager`, the
  scroll-phase event fields and `CVDisplayLink` are all written from their
  documented contracts, but nothing has actually run against the window server.

Run everything that *can* be checked without a Mac:

```bash
./Scripts/verify.sh
```

## Installing

There is no published download yet — the code has not been compiled, so no
release exists to download. Two routes to a `.dmg`:

**Without a Mac.** Push to GitHub and the `Build` workflow compiles on a macOS
runner, attaching `Glide.dmg` to the run as an artifact. Tagging a version
(`git tag v0.1.0 && git push origin v0.1.0`) publishes a draft release instead.

**With a Mac.**

```bash
./Scripts/build-app.sh      # dist/Glide.app
./Scripts/package-dmg.sh    # dist/Glide.dmg
```

Then: open the image, drag **Glide** onto **Applications**, and — because these
builds are ad-hoc signed rather than notarised — **right-click Glide and choose
Open** the first time. A plain double-click is refused. Grant Accessibility
permission when asked.

Distributing it without that right-click step needs an Apple Developer account
(£79/$99 a year) to sign and notarise; `Scripts/package-dmg.sh` prints the
commands.

## Building

```bash
./Scripts/build-app.sh      # produces dist/Glide.app
open dist/Glide.app
```

Requires macOS 13+ and a Swift 5.9 toolchain. Glide needs Accessibility
permission — an event tap will not install without it, and the failure is
otherwise completely silent, so the app checks explicitly and says so.

> macOS ties that permission to the code signature. With ad-hoc signing it
> changes every build, so remove the stale `Glide` entry under
> **System Settings → Privacy & Security → Accessibility** before re-adding it.
> A real Developer ID makes the grant stick.

## Architecture

Three targets, split so the parts that are easy to get subtly wrong stay
testable without a Mac in the loop:

```
GlideCore   Pure Swift. Imports only Foundation.
            Physics, curves, recognisers, the profile model.

GlideKit    The macOS bindings.
            CGEventTap, IOHIDManager, gesture synthesis, display link.

Glide       The SwiftUI app.
```

### Scrolling

Most smooth-scrolling implementations run two systems: an animator that eases
each notch toward a target, and a separate momentum simulation for flings.
Handing off between them is where the seams show.

Glide uses one. Every wheel tick injects an impulse into a single decaying
velocity, sized so its own decay covers exactly the distance the acceleration
curve asked for:

```
v += distance(atCadence:) × friction
```

Because `∫v₀·e^(-kt)dt = v₀/k`, an impulse of `d·k` travels exactly `d`. Three
things fall out of that:

- **The acceleration curve becomes literally true.** "48 points per tick" means
  the content moves 48 points — distance is conserved however the ticks overlap.
- **Momentum stops being a special case.** Ticks arriving faster than the decay
  top the velocity up; stop ticking and the same decay *is* the coast. No
  handoff, so no seam.
- **Frame rate drops out.** `dt` enters an exponent, so 60Hz, 120Hz and a frame
  dropped under load produce identical motion.

The feel is then made real by convincing macOS the events came from a trackpad.
A wheel produces line-based, non-continuous events and views answer those with a
discrete jump; a trackpad produces pixel-precise continuous events carrying a
gesture phase, and views answer *those* with smooth scrolling, overscroll and
rubber-band bounce. Same API, entirely different feel.

### What the harness caught

Writing the Node mirror before trusting the Swift paid for itself four times:

1. **Trapezoid integration drifted.** Integrating each frame with a trapezoid —
   the obvious choice — lost ~0.7pt on a hard fling at 60Hz, worse at 30Hz, and
   let accumulated distance exceed the advertised total. The per-frame integral
   of an exponential is *itself* closed form, so it is now taken exactly: both
   correct and cheaper.
2. **Momentum never emitted `begin`.** One flag was tracking two different
   streams, so the momentum tail opened with `continue`. A view receiving that
   sequence never engages rubber-band bounce.
3. **Momentum-disabled presets dropped ~7% of every notch.** The input timeout
   fired at 90ms and discarded the still-decaying velocity. "No momentum" now
   means no separate momentum *stream*, not a truncated tick.
4. **Resuming mid-coast orphaned the gesture.** Grabbing a coasting page emitted
   `changed` after the gesture had already been closed with `ended`.

### Input recognition

The chord recogniser only waits when waiting can change the answer:

- A button with **no bindings is never intercepted**, so ordinary clicking costs
  exactly nothing.
- A button bound only to a single click **fires on release**, with no
  multi-click delay.
- The multi-click window is **only entered if a multi-click binding exists**.
- A hold fires **at the threshold**, not on release.

If a gesture is swallowed while the recogniser deliberates and then matches
nothing, the click is synthesized back rather than eaten.

### Profiles

Layers stack rather than compete. Most tools make you pick one profile, which
means a per-app profile has to restate every global setting — and then drift out
of sync. Here each layer overrides only the fields it sets, so a per-app layer
that just flips scroll direction says that and inherits the rest.

Configuration is readable JSON at
`~/Library/Application Support/Glide/profiles.json`, written atomically, so it
can be diffed and kept in a dotfiles repo.

## Known gaps

Stated plainly rather than discovered later:

- **Nothing has been compiled or run.** See Status above.
- **Pinch-zoom and space-navigation gestures are stubs.** They need real
  `NSEvent` gesture events (type 29 with the magnify and swipe subtypes) whose
  fields are undocumented and change shape between releases. Rather than guess,
  they currently do nothing.
- **System actions synthesize keyboard shortcuts.** macOS exposes no public API
  for "open Mission Control". The alternative is private CoreDock symbols that
  break between releases; the trade is that an action fails if its shortcut has
  been disabled in System Settings.
- **Device attribution is a heuristic.** `CGEvent` carries no device identifier,
  so IOHID input reports are correlated with events by recency. Reliable in
  practice — a person operates one mouse at a time — but two devices moving
  simultaneously can be misattributed for a frame.
- **Two identical serial-less mice share one identity**, so they cannot have
  separate settings. The alternative is settings that silently reset when a
  device reconnects on a different port.
- **The macro editor lists and deletes but does not yet record.** The playback
  engine and model are complete.
- **`CVDisplayLink` is soft-deprecated** in favour of `CADisplayLink`, which is
  macOS 14+ and tied to a view. Glide's engine is headless and supports macOS 13.

## Layout

```
Sources/GlideCore/     Physics, curves, recognisers, profiles  (Foundation only)
Sources/GlideKit/      Event tap, HID, gesture synthesis       (macOS)
Sources/Glide/         SwiftUI app
Tests/GlideCoreTests/  XCTest suite mirroring the harness
Tools/physics-lab/     Node reference implementation + executable spec
Scripts/               build-app.sh, verify.sh
```

`Sources/GlideCore/Curves/ScrollPreset+BuiltIn.swift` is generated. Every
constant in it is range-checked against perceptual guard rails by
`Tools/physics-lab/presets.js`; regenerate with:

```bash
node Tools/physics-lab/presets.js --swift
```

## Licence

MIT.

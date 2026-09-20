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

## Status

**Builds clean on the `macos-14` runner** — `GlideCore`, `GlideKit` and the app
target all compile, the 66-test suite passes, and a `Glide.dmg` is produced.
CI proves it on every push ([Build workflow](.github/workflows/build.yml)).

**It has not yet been run against a real mouse.** Compiling is not working: the
event tap, HID attribution and gesture synthesis have never met the window
server. Treat the scrolling feel as unproven until someone installs it.

The integration layer has since been hardened against the ways a first run
fails *quietly*: synthesized clicks now carry the real button number (thumb
buttons used to arrive as middle or left clicks), macOS's own wheel-momentum
tail is no longer re-ingested as fresh ticks, a gesture interrupted by an app
switch or a pause now always releases the cursor instead of leaving it hidden
and decoupled, engine errors are surfaced in the menu bar, and the ad-hoc
build carries a stable designated requirement so the Accessibility grant
survives a rebuild. Every failure now has a visible symptom — see
[Troubleshooting](#troubleshooting).

The maths is a different matter — it is mirrored by a Node harness in
[`Tools/physics-lab/`](Tools/physics-lab/) that asserts the same invariants,
runs anywhere, and caught five real bugs (below).

Run everything that needs no Mac:

```bash
./Scripts/verify.sh
```

## Installing

There is no published download yet — the code has not been compiled, so no
release exists to download. Two routes to a `.dmg`:

**Without a Mac.** Every push builds on a macOS runner and attaches `Glide.dmg`
to the run: open the **Actions** tab, pick the run, and download it from the
**Artifacts** section at the bottom. Artifacts keep for 30 days and download as
a `.zip`, so unzip it to get the image.

For a permanent, shareable link instead, tag a version — set `VERSION`, then
`git tag v0.1.0 && git push origin v0.1.0` — and the Release workflow publishes
a draft release with the image attached and install instructions filled in. The
tag has to match `VERSION`; the workflow refuses the release otherwise. See
[Versioning](#versioning).

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
> A real Developer ID makes the grant stick. Glide's build script now embeds a
> stable designated requirement for ad-hoc builds, which means the grant
> survives rebuilds as long as the bundle identifier does not change.

## Versioning

The version lives in one place: the `VERSION` file at the root of the repo,
holding a bare `MAJOR.MINOR.PATCH` number.

`Scripts/build-app.sh` reads it and stamps the bundle as it is assembled —
`CFBundleShortVersionString` is `VERSION` verbatim, and `CFBundleVersion`
appends the commit count (`0.1.0.128`) so two builds of the same release are
still distinguishable to macOS. `Resources/Info.plist` carries only
placeholders; a bundle reporting `0.0.0` was assembled by hand rather than by
the script, and the app's **About** card says so outright.

Everything downstream follows from it: the disk image's volume name, the
version shown in **General → About**, and the Release workflow, which refuses
to publish when the pushed tag disagrees with the file.

To cut a release:

```bash
echo 0.2.0 > VERSION
git commit -am "Release 0.2.0"
git tag v0.2.0 && git push origin HEAD v0.2.0
```

## Troubleshooting

The failure modes a first run hits, in the order they hit:

**Nothing happens at all — the mouse feels exactly as before.** The event tap
is not installed, and the cause is almost always Accessibility. The menu bar
icon still works; open it and the General tab's Status card will say the tap
is **Not installed**. Grant the permission under **System Settings → Privacy
& Security → Accessibility** — and if a stale `Glide` entry is already listed,
remove it first, because macOS keeps denying while a dead entry sits there.
Recent macOS also re-asks for periodic re-approval of apps that intercept
input; a prompt appearing months later is that, not a regression.

**Scrolling is unchanged, but buttons work.** Smoothing is off in the resolved
stack: check the popover's **Enabled** toggle first, then the profile layers —
a per-app profile that sets `smoothingEnabled: false` wins over the global
layer. Profiles shows which layers are contributing right now.

**A thumb button clicks as middle (or as left).** You are running an older
build: the click synthesizer used to lose the button number, because
`CGMouseButton` has no case above middle. Rebuild from this tree.

**Per-device profiles never apply.** The HID manager was denied **Input
Monitoring** (System Settings → Privacy & Security → Input Monitoring). Glide
still scrolls and remaps without it; it simply cannot tell two mice apart.

**Reading deeper.** `GLIDE_TRACE=1` turns on the rate-limited event trace, and
`log stream --predicate 'subsystem == "com.glide.app"'` follows everything the
pipeline does. The General tab also shows whether the tap is installed and how
many times the system has had to pause it.

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

Writing the Node mirror before trusting the Swift paid for itself five times:

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
5. **`projectedDistance` and the simulation disagreed** by a fraction of a
   point. The projection is the travel needed to decay exactly *to* the stop
   threshold, but a frame-stepped fling stops at the first frame *below* it, so
   it always overshoots slightly. The invariant is now a two-sided bound that
   pins the discrepancy to one frame of decay rather than tolerating it.

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

- **Never run against real hardware.** It compiles and its logic is tested, but
  no part of the macOS event pipeline has been exercised on a live system. The
  integration layer is hardened and instrumented (see
  [Troubleshooting](#troubleshooting)), which is not the same thing as tested.
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

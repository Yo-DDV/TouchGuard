# TouchGuard

A native macOS menu-bar app that protects editing from stray pointer clicks,
drag selections and scrolling while typing. Protection begins on key press and
ends **300 ms after the last press/release**. The delay is adjustable from 100 to
1000 ms. Keyboard input is always delivered unchanged.

This is the maintained [Yo-DDV fork](https://github.com/Yo-DDV/TouchGuard) of
[SyntaxSoft's original TouchGuard](https://github.com/thesyntaxinator/TouchGuard).
The new app is independently implemented in C and Objective-C, with no external
runtime dependencies. The inherited implementation is not compiled or installed.

## Requirements

- macOS 14 or later, Apple silicon or Intel.
- Accessibility permission for TouchGuard.
- Xcode Command Line Tools or Xcode to build from source.

## Build and install

```sh
git clone https://github.com/Yo-DDV/TouchGuard.git
cd TouchGuard
bash scripts/test.sh build/tests
bash scripts/build.sh build/app
```

Copy `build/app/TouchGuard.app` to Applications and open it. Grant TouchGuard
access in **System Settings → Privacy & Security → Accessibility**, then choose
**Retry Protection** if necessary. Enable **Start at Login** in its menu. macOS
manages that user service, including relaunch after a crash; no root service or privileged installer is
required. The build script refuses to overwrite an existing app: use a fresh
output directory for a subsequent build.

Local builds use an ad-hoc signature by default. Publishers can set
`SIGNING_IDENTITY` to a Developer ID identity to use hardened runtime and a secure
timestamp. A locally compiled signature is not a claim of Apple notarization;
downloaded releases require a separate notarization process. Never disable
Gatekeeper or quarantine checks to run an untrusted binary.

## Controls

- **Protect While Typing**: pause or resume without changing keyboard behavior.
- **Delay After Typing**: choose the short release delay.
- **Start at Login**: use native macOS registration and crash recovery. Disabling it stops the managed instance.
- **Retry Protection / Accessibility Settings**: resolve a denied or newly granted permission.
- **Quit TouchGuard**: stop the session's protection.

The menu reports whether protection is active and shows an aggregate blocked
interaction count. Settings persist; input contents and counters do not.

## Validation

```sh
# Configuration/permission status; no event contents are printed.
/Applications/TouchGuard.app/Contents/MacOS/TouchGuard --status

# With TouchGuard running and Accessibility granted, a short disposable window
# checks native click delivery before, during and after the protection window.
# Leave that window focused until it closes automatically.
/Applications/TouchGuard.app/Contents/MacOS/TouchGuard --integration-test
```

CI runs isolated tests, sanitizers, strict universal builds and static analysis
on Intel, Apple silicon and the current Xcode preview. Resource claims for the C
core are microbenchmarks; whole-app CPU and memory must be measured on the running
target, rather than inferred from compilation or state tests.

## Scope and privacy

The guard filters pointer events from both trackpads and mice. It prevents the
clicks and drags that move the text caret or select text; it does not freeze the
system cursor or block system multi-finger gestures. Command/Control/Option
gestures bypass suppression. Secure Input is respected and may temporarily make
protection unavailable in protected fields. See [SECURITY.md](SECURITY.md).

To uninstall, disable Start at Login, quit the app, remove its Accessibility
entry, then remove the application. No system configuration or shared input
utility needs to be changed.

## License and provenance

The independently implemented app, tests, scripts and new documentation are
licensed under MIT; see [LICENSE](LICENSE). The inherited `TouchGuard/` and
`TouchGuard.xcodeproj/` files and upstream history are excluded because upstream
did not provide an explicit license. They are retained unmodified for provenance.

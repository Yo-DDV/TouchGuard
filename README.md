# TouchGuard

A native macOS background app that protects editing from stray pointer clicks,
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
access in **System Settings → Privacy & Security → Accessibility**. Protection
starts automatically after consent. If the two-minute consent window has ended,
run `--resume` using the command below. Enable startup with `--enable-login`.
macOS manages this user service, including relaunch after a crash; no root service
or privileged installer is required. The build script refuses to overwrite an existing app: use a fresh
output directory for a subsequent build.

Local builds use an ad-hoc signature by default. Publishers can set
`SIGNING_IDENTITY` to a Developer ID identity to use hardened runtime and a secure
timestamp. A locally compiled signature is not a claim of Apple notarization;
downloaded releases require a separate notarization process. Never disable
Gatekeeper or quarantine checks to run an untrusted binary.

## Controls

There is no menu-bar icon or Dock icon. Controls run from Terminal:

```sh
tg=/Applications/TouchGuard.app/Contents/MacOS/TouchGuard
"$tg" --enable-login
"$tg" --delay-ms 300  # 100 to 1000 ms; saved across sessions
"$tg" --pause
"$tg" --resume       # also retries access after granting consent
"$tg" --status
"$tg" --stop         # normal exit; no immediate restart
"$tg" --disable-login
```

Settings changes reach the running app through a local notification, with no
polling or network listener. Only an enable flag and delay are stored.
`--status` reports configuration, process presence and permissions; the native
diagnostic below verifies actual filtering. Disabling startup stops the managed
instance; the app can still be opened manually.

## Validation

```sh
# Configuration/permission status; no event contents are printed.
/Applications/TouchGuard.app/Contents/MacOS/TouchGuard --status

# With TouchGuard running and Accessibility granted, a short disposable window
# checks click, drag and scroll delivery before, during and after protection.
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

To uninstall, run `--disable-login` and `--stop`, remove its Accessibility
entry, then remove the application. No system configuration or shared input
utility needs to be changed.

## License and provenance

The independently implemented app, tests, scripts and new documentation are
licensed under MIT; see [LICENSE](LICENSE). The inherited `TouchGuard/` and
`TouchGuard.xcodeproj/` files and upstream history are excluded because upstream
did not provide an explicit license. They are retained unmodified for provenance.

# Security and privacy

The native app is independently implemented in `modern/`. The original C source
and Xcode project remain in the fork for provenance and are not part of the build.

## Input and privileges

- The keyboard tap is **listen-only** and subscribes only to press/release events.
  It records a monotonic deadline. It never extracts key codes, characters,
  passwords, document content, clipboard data or application titles.
- The pointer tap drops clicks, dragging and scrolling during that deadline.
  Matching releases remain suppressed even after expiry, pause or a delay change.
- The app runs as the signed-in user. Accessibility is granted through macOS;
  there is no root daemon, elevation, passwordless rule or TCC database editing.
- Protected input is respected. The guard fails open while macOS Secure Input
  prevents observation of keyboard events.
- No third-party libraries, downloads, network client, telemetry or updater are
  present. Only Apple system frameworks are linked.
- Preferences store only an enable flag and the delay. Local notifications carry
  no input or configuration data; the app reloads its own user preferences.
  The stop notification only requests a normal exit. There is no network listener.

## Availability and energy

The filter uses fixed-size state and a timestamp comparison. It has no per-key
allocation, timer, file write or busy loop. The only polling is a bounded
two-minute permission retry **before activation**; that timer stops once the
event taps are established. Sleep/wake and event-tap timeout recovery reset
temporary state. Keyboard events are never suppressed.

The native `SMAppService` user agent starts the app when the user signs in and
restarts an abnormal exit through macOS, with a ten-second throttle. It does
not enable protection before a GUI session exists. There is no menu-bar or Dock
icon. Terminal commands pause, resume, configure or stop it. A normal stop
does not cause an immediate restart. Disabling the login service stops its
managed instance; the app can still be opened manually.

## Tests and audit scope

The state-machine test runs with network and filesystem writes denied, followed
by AddressSanitizer/UndefinedBehaviorSanitizer checks. Builds use strict compiler
warnings, native static analysis and universal arm64/x86_64 output. The checkout
action is pinned to an immutable revision with read-only repository permissions.

`--integration-test` is an explicit diagnostic mode. It opens a disposable window,
posts known synthetic input, measures its own handlers, closes the window and
restores the previous app. It checks focus before posting and cancels if focus
changes. Do not switch applications during this short diagnostic. Normal app
startup never enters this mode and never synthesizes input.

The production app cannot use Apple's App Sandbox because global input filtering
requires Accessibility access. Isolated unit tests do not claim to prove OS input
delivery: the native diagnostic must be run with consent on the target system.

## Platform boundaries

Public Core Graphics events do not reliably identify the physical mouse versus
trackpad. The guard consequently applies to the session's pointer clicks and
scrolling from either device. Command/Control/Option gestures are deliberate
bypasses; Shift does not bypass protection. It does not physically disconnect a
trackpad or freeze the system cursor, and does not intercept system gestures such
as Mission Control or pinch-to-zoom. Its purpose is to prevent accidental clicks
and selections from altering text while typing.

No audit can guarantee the absence of future defects. Report reproducible
security problems without private input data or credentials.

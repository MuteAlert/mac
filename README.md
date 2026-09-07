# MuteAlert for macOS

Native Swift/AppKit menu-bar port of [MuteAlert for Windows](https://github.com/MuteAlert/windows).
Requires macOS 13 or newer. Builds a universal Apple Silicon + Intel app.

**Initial development port, not a store-ready release.** CI checks compilation and pure-logic tests;
real microphone devices, headset buttons and live calls still need testing on a Mac.

## Features and port status

| Feature | macOS implementation |
| --- | --- |
| Bottom-to-top microphone activity icon | Local AVAudioEngine peak meter, explicitly enabled in Settings |
| Input volume, scroll control and volume lock | Core Audio master input volume, when exposed by the device |
| System microphone mute | Core Audio master mute, when exposed by the device; no fake app-only mute fallback |
| Separate call icon, focus and mute toggle | App icon and bounded Accessibility scans; experimental |
| Slack, Teams and Zoom | Opt-in configurable Accessibility button-label detection; requires live validation |
| Google Meet | Opt-in foreground-browser window only, with title, leave-call and unique microphone-button checks |
| Speaking-while-muted warning and audio cue | Local threshold/delay detector, notification and optional sound |
| Standard HID headset controls | Non-exclusive telephony/system-control mute button events; physical latched state unknown |
| Vendor headset protocols | Adapter interface present; Windows SteelSeries report decoder retained and tested, macOS transport **not implemented** |
| Diagnostics | VID/PID, parsed HID element descriptor fields and sanitized mute-button changes |
| GitHub update checks | Optional daily checks and manual release download; **no automatic installer** |
| Launch at login | macOS SMAppService login item |

Core Audio mute can reflect a driver/hardware change, but does not establish whether a physical switch caused it.
Silence is never interpreted as physical mute. Generic HID synchronization is opt-in and best-effort:
not all headsets expose buttons, and vendor protocols require device-specific work.
It does not provide universal bidirectional physical-switch synchronization.

## Controls

- Microphone icon: left-click toggles system input mute; scroll changes input volume.
- Call icon: left-click focuses its app; right-click toggles detected call mute.
- Microphone right-click also toggles an active call, or opens the menu if none is detected.
- Control-click either icon opens Settings/Quit. Middle-click opens the same menu.
- Hover displays the input name, volume and available controls.

Some inputs, including built-in or USB microphones, may not expose master mute/volume controls.
Unsupported controls report an explanation in Settings. This app cannot override a physical mute switch.

## Permissions and privacy

Enable the meter in Settings to request Microphone permission. Audio is analyzed in memory and
is never recorded, saved or uploaded. An active meter causes macOS's normal microphone privacy indicator.
Call integrations require Accessibility permission. HID access can require Input Monitoring permission.
Notifications require notification permission. Integrations and meter are disabled initially.

Call scans inspect only configured running applications. Meet scans only the foreground browser,
not every browser window in the background. No call text, window titles, serial numbers, audio,
device paths or raw HID reports are exported. Diagnostics contain device IDs and descriptor fields;
review an export before attaching it publicly.

Release checks contact GitHub only when requested or enabled, exposing normal request metadata such as
your IP address. There is no analytics service. Preferences remain in local macOS UserDefaults.

## Build and test

On a Mac with Xcode command-line tools:

```sh
swift test
bash scripts/build.sh
```

The bundle is `dist/MuteAlert.app`; the distributable is `dist/MuteAlert-mac-universal.zip`.
CI uploads the ZIP as an Actions artifact. Launch the bundled app, not the bare Swift executable,
so macOS can associate permissions with its bundle identity.

Development builds are ad-hoc signed, **not Developer ID signed or notarized**. Public distribution
needs proper signing/notarization; this project is not yet approved for the Mac App Store.
Automatic updates should be added only with an authenticated, signed update/install pipeline.

## Validation checklist before a public release

- Test Intel and Apple Silicon, device changes, sleep/wake and permission denial/revocation.
- Test supported and unsupported input controls; verify no unrelated mic or call is changed.
- Validate each call app's current labels and supported languages; test ambiguous and missing controls.
- Validate headset native handling alongside opt-in synchronization to detect double toggles.
- Validate menu placement, focus, scrolling and tooltips on multiple displays.
- Obtain signing/notarization and test installation, permissions and login registration.

## License

PolyForm Shield 1.0.0, matching the Windows project. See [LICENSE.md](LICENSE.md) and [NOTICE](NOTICE).
Source-available; not an OSI-approved open-source license.

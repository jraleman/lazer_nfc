# LaZer NFC iOS reader

This is a real **Core NFC** plugin for Godot's iOS export, not an NFC
simulation. It runs an `NFCTagReaderSession` polling ISO 14443, ISO 15693 and
ISO 18092, and reads only hexadecimal tag identifiers. It does not read NDEF
records, write tags, log identifiers or send data over a network.

Core NFC is available on **iPhone 7 and newer**; no iPad has a reader. The
game installs and plays on every device, falling back to keys and touch.

## What is different from Android

Core NFC is not a background reader. Every scan is a system-owned modal sheet
that covers the game, swallows touches and can only be dismissed with its own
**Cancel** button. Three consequences drive the design here:

| Android | iOS |
| --- | --- |
| Silent background reader mode. | Mandatory system sheet; only its text is ours. |
| Platform scan sound disabled. | System detection sound cannot be disabled. |
| `EXTRA_READER_PRESENCE_CHECK_DELAY` dedupes a resting tag. | No presence API; this plugin emulates one (below). |
| A user-facing NFC toggle exists. | No toggle; only Airplane Mode reports a disabled radio. |
| Session runs until stopped. | Session expires after roughly a minute and is reopened. |

## Build

iOS plugins are static libraries compiled against the engine's own headers, so
this step **requires macOS with Xcode** — it cannot run on Windows or Linux.

```bash
cd godot-base/games/lazer_nfc/ios
chmod +x build_plugin.sh            # once, if Git did not preserve the bit
./build_plugin.sh --godot-source ~/src/godot
```

`--godot-source` must point at a **Godot 4.7.2** checkout — the version the
export templates were built from. The script refuses anything else, because a
plugin compiled against mismatched engine headers links but corrupts object
layout at runtime; set `LAZER_NFC_ALLOW_VERSION_MISMATCH=1` only if you are
deliberately building your own templates from that same tree.

A clean checkout is usually enough: the script shadows the generated headers it
knows about (`core/version_generated.gen.h`, `modules/modules_enabled.gen.h`,
`core/disabled_classes.gen.h`) in its own scratch include directory rather than
writing into the engine tree. If clang still reports a missing `*.gen.h`, run
`scons platform=ios` in the checkout once to generate the full set.

The script builds `debug` and `release`, each as an `.xcframework` containing a
device slice (`arm64-apple-ios15.0`) and a fat simulator slice
(`arm64` + `x86_64`). The simulator slice compiles with Core NFC disabled —
there is no simulator radio — and honestly reports unsupported hardware, so a
simulator run still exercises the keyboard and touch fallback.

Pass `--config release` to build one target, or `--clean` to discard `build/`.
Staging still requires **both** configurations to be present: `lazer_nfc.gdip`
names an unsuffixed binary, which Godot only resolves per target when both
`lazer_nfc.debug.xcframework` and `lazer_nfc.release.xcframework` exist. They
cannot be mirrored from one another, because `DEBUG_ENABLED` changes engine
object layout.

## Staging

Godot scans `<host project>/ios/plugins` and recurses exactly **one** level.
That path belongs to the host project, so a game folder cannot own it. The
build script therefore stages its artefacts the same way the Android build
stages its AAR:

```text
godot-base/ios/plugins/lazer_nfc/lazer_nfc.gdip
godot-base/ios/plugins/lazer_nfc/lazer_nfc.release.xcframework
godot-base/ios/plugins/lazer_nfc/lazer_nfc.debug.xcframework
```

The `.gdip`'s `binary="lazer_nfc.xcframework"` plus the `.release`/`.debug`
files on disk is what lets Godot pick the slice matching the export target.
Build outputs are ignored by Git; the `.gdip` source of truth lives here.

## Host export integration

The host project registers `res://games/lazer_nfc/ios/plugin.cfg` in
`[editor_plugins]`, and its **`iOS - LaZer NFC`** preset declares the
`lazer_nfc` custom feature. The editor-plugin registration is required; the
preset's `plugins/LazerNfc` flag alone does not add the export behaviour below.

`export_plugin.gd` supports iOS only and checks the exporting preset's feature
list rather than the editor's runtime features, so unrelated iOS games are
untouched. For the tagged preset it:

- fails the export, listing exactly what is missing, when the staged `.gdip` or
  either `.xcframework` is absent — an unbuilt plugin must never produce an
  apparently NFC-capable app;
- forces `plugins/LazerNfc = true`;
- writes the NFC reader entitlement into the generated `.entitlements` file if
  the preset did not already carry it. Godot exposes **no API** for
  contributing entitlements, and a build without this key terminates the
  moment a scan starts, so the generated project is repaired rather than
  trusted;
- reminds you about the provisioning profile, which Godot cannot set.

### Three things Godot cannot do for you

1. **App ID capability.** Enable *Near Field Communication Tag Reading* on App
   ID `com.deskcansaw.lazernfc` in the Apple Developer portal and re-download
   the provisioning profile. Without it, codesign succeeds and installation
   fails.
2. **Team ID.** `application/app_store_team_id` is one of only two required
   preset fields (with `application/bundle_identifier`) and ships empty, so the
   export stops with *"App Store Team ID not specified"* until you fill it in.
3. **The `.ipa`.** Exporting from Windows or Linux produces the Xcode project
   only; `xcodebuild` and one-click deploy are macOS-only.

A command-line export from the game folder is:

```bash
godot --headless --path ../.. --export-debug "iOS - LaZer NFC" /path/to/build/ --quit
```

The preset targets **iPhone only** (`application/targeted_device_family=0`),
keeps the Godot 4.7 minimum deployment target of **15.0**, includes this game's
recorded tutorial, and excludes other games, development sources and both
plugin folders. `nfc` is deliberately **not** added to
`capabilities/additional`: listing it in `UIRequiredDeviceCapabilities` would
stop NFC-less iPhones from installing a game they can fully play, exactly as
`android:required="false"` avoids on Android.

## Runtime contract

`Engine.get_singleton("LazerNfc")` exposes the same four methods as the Android
reader — `is_supported()`, `is_enabled()`, `enable_reader()`,
`disable_reader()` — so `input/nfc_source.gd` needs no platform branch. Two
methods and one signal are iOS additions, discovered with `has_method` and
`has_signal` rather than by checking the platform:

| Member | Meaning |
| --- | --- |
| `tag_discovered(uid: String, age_ms: int)` | Canonical lowercase hex UID and compensated elapsed age. |
| `adapter_state(enabled: bool)` | Radio availability; on iOS only Airplane Mode turns it off. |
| `reader_error(message: String)` | A meaningful native failure. |
| `reader_cancelled` | *iOS.* The player dismissed the scanning sheet. |
| `set_prompt(text: String)` | *iOS.* Text shown inside the scanning sheet. |
| `is_modal() -> bool` | *iOS.* True when scanning covers the screen. |

`is_supported()` reports `NFCTagReaderSession.readingAvailable`. UIDs come from
`.miFare`, `.iso7816` and `.iso15693` tags without connecting; anything empty
or longer than 32 bytes is reported as an unreadable tag rather than guessed
at.

FeliCa is deliberately not polled. `NFCPollingISO18092` requires
`com.apple.developer.nfc.readersession.felica.systemcodes` in `Info.plist`, and
an app that polls it without enumerating a system code has its whole session
invalidated with a security violation — so asking for FeliCa would break every
scan rather than merely skipping Japanese transit cards.

Every mutable field is owned by the main thread. Delegate callbacks arrive on a
private serial queue and hop to the main queue before touching Godot, and the
session this reader closes itself is remembered so its own invalidation is
never misread as a fault.

### Cancellation is a choice, not a failure

The sheet blocks every touch, so its Cancel button is the only way out of a
scan. `reader_cancelled` therefore revokes the request and emits
`NfcSource.scan_cancelled`; the hardware stays *available*. `gameplay.gd`
switches that run to keys and touch, leaves the run model intact — a sequence
in progress is still answerable — and opens the pause menu. Because
`_physical_run` is now false, closing the pause menu does not reopen the sheet.

Unlike a scan, the cancellation is not epoch-scoped: `NfcSource` calls `stop()`
synchronously in the signal handler and defers only the outward notification.
Deferring the revocation would let a pause or a `reset_debounce()` in the same
frame advance the callback epoch, drop the cancellation, and leave the request
standing for the next resume to reopen the sheet with.

### Emulated presence check

Core NFC has no equivalent of Android's presence-check delay, and a tag resting
on the phone is rediscovered after every `restartPolling()` *and* after every
session renewal. Left alone that would answer the same robot several times a
second.

After reporting a UID the reader **pins** that identifier and **connects** to
the tag, then polls `NFCTag.isAvailable` every 250 ms. Once the tag leaves, the
pin is dropped and polling restarts. A rediscovery of the pinned identifier is
silently swallowed, so the ceilings below only cost latency, never a duplicate
answer:

- the removal poll gives up after **5 s**, so a tag whose `isAvailable` sticks
  cannot hold the field; the rediscovery that follows re-pins it;
- the pin itself expires **8 s** after the tag was last seen, so a tag that is
  never seen again — a failed connect, or a stuck `isAvailable` on a tag that
  really did leave — can be scanned again instead of being suppressed forever.

A failed connect falls back to Apple's own 500 ms restart delay.

### Session and lifecycle

Core NFC grants roughly a minute per session. `SessionTimeout` and
`SessionTerminatedUnexpectedly` reopen after 0.6 s; `SystemIsBusy` retries
three times at 1.5 s before surfacing an error; `RadioDisabled` reports the
radio as off and is re-checked when the app returns to the foreground.

Only `UIApplicationDidEnterBackgroundNotification` stops the reader.
`applicationWillResignActive:` is deliberately **not** observed: presenting the
system sheet can resign the active state, and treating that as the player
leaving would close the sheet the moment it opened. This matches Godot, which
emits `NOTIFICATION_APPLICATION_PAUSED` only from `didEnterBackground`.

Native age is the uptime at discovery subtracted from the uptime at handoff,
plus the same **80 ms estimated RF latency** the Android reader uses, so one
age contract covers both platforms. Godot adds only its own deferred queue
duration, and the 80 ms estimate is never added twice.

`Input.vibrate_handheld` is implemented on iOS 13+ through Core Haptics with
both duration and amplitude honoured, so `audio/haptics.gd` drives iPhones and
Android phones identically. A device with silent mode, Do Not Disturb or system
haptics off can still suppress it, which is why haptics are never the only
confirmation of a read.

## Validation boundaries

The focused headless regressions are
`res://games/lazer_nfc/tests/lazer_nfc_input_test.gd` and
`res://games/lazer_nfc/tests/lazer_nfc_bindings_test.gd`, run from the host
with `godot --headless --path . --script <script> -- --game=all`. The input
test injects a modal fake plugin covering prompt forwarding, cancellation and
the lifecycle callbacks that must **not** reopen a dismissed sheet. They do
**not** compile this Objective-C++, and they cannot validate a radio, the
system sheet or real RF timing.

An iPhone 7 or newer is required to establish tag compatibility, sheet
behaviour during a live round, the emulated presence check against real tags,
session renewal across the one-minute cap, Airplane Mode handling and that
backgrounding closes the sheet.

Worth instrumenting on that first device run: whether presenting the sheet
emits `NOTIFICATION_APPLICATION_FOCUS_OUT`. Godot stops rendering and stops the
audio driver on focus loss, so if it does, the game freezes visually and goes
silent while the sheet is up. That is an engine-level behaviour, not an NFC
bug, but it decides whether a scan during a live round is playable.

## Upstream references

- [Godot iOS plugins](https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html)
- [Godot iOS export options](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformios.html)
- [Core NFC `NFCTagReaderSession`](https://developer.apple.com/documentation/corenfc/nfctagreadersession)
- [Building an NFC tag-reader app](https://developer.apple.com/documentation/corenfc/building-an-nfc-tag-reader-app)
- [Near Field Communication Tag Reader Session Formats entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.nfc.readersession.formats)
- [`NFCReaderUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nfcreaderusagedescription)

# LaZer NFC Android reader

This is a real **Godot Android v2** plugin, not an NFC simulation. It uses
`NfcAdapter.enableReaderMode` for NFC A/B/F/V, skips NDEF reads and disables
Android's platform scan sound. It reads only hexadecimal tag IDs. It does not
write tags, log their IDs, register foreground-dispatch intents or send data
over a network.

## Build

Run from `godot-base\games\lazer_nfc\android` in PowerShell:

```powershell
.\gradlew.bat --gradle-user-home .\.gradle-user-home --no-daemon clean stageRelease
```

The checked-in wrapper downloads **Gradle 8.13** from Gradle's official service
and verifies the pinned distribution SHA-256. No global Gradle installation is
needed. The command keeps Gradle downloads and caches inside this directory.

The build requires a **JDK 17** (including `javac`), Android SDK Platform **36**
and Android SDK Build-Tools **36.1.0**, with their Android SDK licences accepted.
The Android Gradle Plugin is pinned to **8.13.2**. The only engine dependency is
the published Maven Central artifact
`compileOnly "org.godotengine:godot:4.7.2.stable"`; Godot itself is supplied by the
host export template, not copied into this AAR. No NDK or CMake is needed to
compile this Java-only plugin.

If the tools are already installed but not discoverable, select them **only
for the current PowerShell process** before running the command:

```powershell
$env:JAVA_HOME = "C:\path\to\jdk-17"
$env:ANDROID_HOME = "C:\path\to\Android\Sdk"
.\gradlew.bat --gradle-user-home .\.gradle-user-home --no-daemon clean stageRelease
```

Alternatively, put `sdk.dir=C:\\path\\to\\Android\\Sdk` in this directory's
ignored `local.properties`. Do not commit machine paths or change the global
environment. Provision SDK/JDK tools separately; the build does not install
system tools (`android.builder.sdkDownload=false` prevents automatic SDK
provisioning). Gradle dependency downloads use only the official Gradle,
Google Android and Maven Central repositories.

The release artifact is staged at:

```text
res://games/lazer_nfc/android/bin/lazer-nfc-release.aar
```

The original Gradle output is
`build\outputs\aar\lazer-nfc-release.aar`. `clean` removes both the build output
and the staged release, so a failed clean rebuild cannot leave an old reader
masquerading as its new output. Generated AARs and machine-local caches are
ignored by Git.

## Host export integration

The host project registers
`res://games/lazer_nfc/android/plugin.cfg` in `[editor_plugins]`, and its
Android preset declares the **`lazer_nfc` custom feature** and uses Gradle
export. The editor-plugin registration is required; a preset's
`plugins/lazer_nfc/enabled` flag alone does not register this v2 plugin. Host
`project.godot` and preset configuration are intentionally outside this plugin.

Inspect the existing `godot-base\android\.build_version` and
`godot-base\android\build` before provisioning tools or installing a template.
Reuse the matching **4.7.2** host template, its engine AARs, Gradle wrapper and
existing SDK references. Install a template only if it is absent or mismatched.
The host APK project and this game-owned reader-library project are separate:
do not replace the host wrapper with this directory's wrapper. The host
template's `config.gradle` can declare additional prerequisites, such as an
NDK, which the Java-only reader build does not need.

`export_plugin.gd` supports Android only, checks the exporting preset's feature
list rather than the editor's runtime features, and enforces Gradle for that
tagged preset. Unrelated Android games receive no AAR or manifest additions.
Missing AARs are reported as export errors **and remain mandatory Gradle
dependencies**, never silently filtered out. Build the AAR before exporting.

`_get_android_libraries()` explicitly returns the reader AAR to Godot's Android
exporter. The host template consumes it through `plugins_local_binaries` and
`implementation files(...)`, independently of PCK resource filtering.
Excluding `games/lazer_nfc/android/*` from exported resources is therefore
correct: the build sources stay out of the PCK while Gradle still packages the
reader and merges its manifest. The plugin's minimum Android SDK is 24; the
APK's target SDK remains controlled by the parent export preset.

The AAR's `src\main\AndroidManifest.xml` supplies all manifest additions:
`android.permission.NFC`, `android.permission.VIBRATE`, optional
`android.hardware.nfc` (`required="false"`) and the
`org.godotengine.plugin.v2.LazerNfc` entry pointing to
`com.deskcansaw.lazernfc.LazerNfc`. NFC-less phones can therefore install the
game and use its keyboard/touch fallback.

After staging the AAR, a command-line debug export from the game folder is:

```powershell
godot --headless --path ..\.. --export-debug "Android - LaZer NFC" "C:\path\to\LaZerNFC-debug.apk" --quit
```

Choose an existing output directory. `--quit` requests an exit after the
export. The preset includes this game's
recorded tutorial and excludes other games and development sources. A debug
APK packages the reader, NFC/VIBRATE permissions and optional NFC feature;
it is not a substitute for the physical-device acceptance below.

## Runtime contract

`Engine.get_singleton("LazerNfc")` exposes `is_supported()`, `is_enabled()`,
`enable_reader()` and `disable_reader()`. Its signals are:

| Signal | Meaning |
| --- | --- |
| `tag_discovered(uid: String, age_ms: int)` | Canonical lowercase hex UID and compensated elapsed age. |
| `adapter_state(enabled: bool)` | A radio-state change or freshly observed activity state. |
| `reader_error(message: String)` | A meaningful native failure, also sent to Android's error log. |

`input\nfc_source.gd` is the scene-owned adapter. Connect `tag_scanned`,
`availability_changed` and `reader_error` **before** `add_child()` to receive
the initial availability result. `available()` describes the device.
`start()`, `stop()` and `reset_debounce()` control the active scan window.
No source starts merely because it was added to the tree. `no_plugin`,
`no_hardware` and `disabled` are ordinary availability states, not errors.
Tests can inject a plugin object and a millisecond clock via
`NfcSource.new(fake_plugin, fake_clock_callable)`.

The native side keeps the game request separate from activity resume/pause.
Every reader-mode call runs through `Activity.runOnUiThread`. The protected
adapter-state broadcast receiver is registered once per active lifecycle and
unregistered on pause/destruction. Discovery callbacks carry an internal
generation to the Godot render thread; stop/pause invalidate it immediately.
The source additionally captures its own generation before deferring a scan,
stops on scene exit and tree/application pause, and drains a process frame of
pending callbacks before resetting debounce on resume. Losing availability
revokes the reader request in both the source and native plugin. Restored
availability is only a notification: the parent must explicitly call `start()`
after choosing the appropriate active window. Radio off/on events retain their
observed state across the render handoff, even when the switch happens quickly.

Native age is `elapsedRealtime()` at render handoff minus
`elapsedRealtime()` at discovery, plus the **80 ms estimated RF latency**.
Godot adds only its own deferred queue duration. Absolute Android and Godot
clock epochs are never compared and the 80 ms estimate is never added twice.
Repeated reads of one UID are suppressed for **500 ms**, including when a
different tag was read in between; a different UID is not held behind a global
cooldown. The model owns any subsequent recall-window judgement.

`run\tag_bindings.gd` accepts only complete ASCII hexadecimal bytes, lowercases
them, validates the 21 palette IDs, and saves `[tags]` UID-to-colour entries in
`user://lazer_nfc_tags.cfg`. Saves merge against a freshly validated file and
atomically replace it, preserving unrelated sections and skipped shade/hue
tags. Rebinding a colour removes its obsolete UID; a UID belonging to another
colour is rejected by default. An explicit prompted roll call may use
`bind_tag(uid, color_id, true)` (`allow_reassignment` defaults to `false`) to
relabel that UID. The previous owner and the new colour's obsolete UID are
intentionally removed on merge-save, including across several unsaved changes;
skipping other colours preserves their bindings. The parent tracks UIDs already
seen in that roll call so one physical tag cannot fill two prompts.

A failed-read path stays protected on the same `TagBindings` object until a
repaired file is explicitly loaded successfully. Reassignment does not clear
that guard; do not clone the map into another object to bypass it. Keyboard and
touch skip physical setup entirely and never create stored UIDs. The parent
owns the active-shell and roll-call clocks, not these input sources.

## Validation boundaries

The focused headless regressions are
`res://games/lazer_nfc/tests/lazer_nfc_input_test.gd` and
`res://games/lazer_nfc/tests/lazer_nfc_bindings_test.gd`, run from the host with
`godot --headless --path . --script <script> -- --game=all`. They exercise
injected availability, debounce, callback age, pause/stop/scene-exit races,
live key bindings, neutral motion and safe tag persistence in named temporary
`user://` fixtures. They do **not** validate an Android radio or real RF timing.

An Android device is still required to establish tag technology compatibility,
actual callback latency, no platform ding, radio toggling, background/foreground
behaviour and the absence of reader mode after returning to menus.

## Upstream references

- [Godot v2 Android plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html)
- [Godot 4.7.2 Android library](https://repo.maven.apache.org/maven2/org/godotengine/godot/4.7.2.stable/)
- [Android reader mode](https://developer.android.com/reference/android/nfc/NfcAdapter#enableReaderMode(android.app.Activity,android.nfc.NfcAdapter.ReaderCallback,int,android.os.Bundle))
- [Android Gradle Plugin 8.13 compatibility](https://developer.android.com/build/releases/agp-8-13-0-release-notes)
- [Gradle wrapper](https://docs.gradle.org/8.13/userguide/gradle_wrapper.html)

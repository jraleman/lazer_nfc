# LaZer NFC

A memory game in a warm, handmade toy laboratory. Watch the little robots play
a melody, then recall their colours in order to fire the laser. Every colour
also has a shape and an instrument. The recall robots hide all three answers.

This is a game folder inside the Godot 4.7 DCS base, not a second Godot project.
It uses the shared title screen, settings, pause, results, achievements and
scorecard. The archived implementation is not a dependency.

## Play

From this folder:

```powershell
godot --headless --path ..\.. --editor --import --quit
godot --path ..\.. -- --game=lazer_nfc
```

The normal studio sting and skippable laboratory briefing lead to the main
menu. **Play** opens instructions, then the game. The instructions can be
disabled with the framework's usual setting.

Try the colours in **READY** before pressing **Start experiment** or Space.
**Learn the sounds** also turns NFC taps into free instrument previews.
Practice costs no lives and never flags a run Assisted.

| Action | Default |
| --- | --- |
| Red / orange / yellow / green / blue / indigo / violet | 1 / 2 / 3 / 4 / 5 / 6 / 7 |
| Start an experiment; skip a tag prompt | Space |
| Dark / light shade, held with a colour key | Q / E |
| Pause | Esc, or the shared pause button on a touchscreen |
| Touch colours | Labelled shape buttons; Dark / Base / Light selector in shade mode |

All gameplay keys can be rebound in **Settings > Controls**. The colour deck
shows the current bindings. Both shade keys held together select the base
shade, rather than depending on key order. Holding a colour key does not
repeat answers.

The default first palette is red, yellow, green and blue: keys **1, 3, 4, 5**,
not the first four number keys. Numbering never changes as colours join.

## One more experiment

Each experiment starts with three batteries and a three-robot sequence.
The show ends with a double recall cue. Answer each grey robot before its
shrinking window runs out. A wrong colour costs a battery but leaves the
same robot on its original deadline. A timeout costs a battery and the
robot escapes; even an escape on the last robot advances cleanly.

Every round adds a robot, up to twelve. More colours join on rounds 3, 5 and 7,
and recall windows tighten without falling below two seconds. Fast answers,
consecutive hits and clean rounds increase the score. A clean sweep doubles
the round bonus. Measured reach motion adds a bonus on supported phones, but
motion is never required to answer correctly.

At twelve robots the pattern rolls: the oldest cue drops away and a new
ending joins the other eleven. Deep runs keep asking for fresh memory rather
than repeating the same solved melody forever.

Touch answers mark the whole experiment **Assisted** and halve its score
once, including points already earned. Keyboard and NFC use full scoring.
That distinction appears in results and sharing; merely trying the pad in
READY has no penalty.

Zero batteries opens the real shell results and scorecard. **Play Again**
resets the complete experiment. Leaving a live run does not award achievements.
Difficulty changes take effect next experiment; voice, haptics, pad visibility,
key labels and visual accessibility options update immediately.

## NFC setup

NFC is optional. An ordinary desktop, web build or NFC-less phone starts with
working keys and a touch pad; it never waits for imaginary tag scans.

The Android reader uses tag UIDs only, not NDEF payloads. On a phone with NFC
enabled, the game asks for tags when fewer than three distinct hues are bound,
or **Settings > Game > Rebind tags** has been requested. A prompt can be
skipped, times out after twelve seconds, and always offers **Use keys / touch**.
That explicit fallback choice survives Play Again in the same scene; a new
Rebind tags request switches back to physical setup.
Skipping keeps an existing binding. A deliberate roll call can relabel a tag,
but one tag cannot serve two prompts in the same roll call.

Print `assets/tag-sheet.svg`, attach real NFC stickers to the backs, and bind
them in the game. The printed page itself is not an NFC tag. Start with the
seven base labels; all fourteen dark/light instruments are also included.
Keep tags at least 15 cm apart, on non-metallic surfaces and comfortably
within reach. Ferrite-backed tags work on metal. Locate the phone's actual
antenna during setup; lift the phone before repeating a tag.

In READY, double-scan the **same tag** for these shortcuts:
red toggles shades, yellow toggles the touch pad, violet starts rebinding.
The first scan of one of those tags briefly waits for a possible second scan;
other tags or the Start button begin immediately. Shortcuts write the same
settings as the Game tab.

Bindings merge into `user://lazer_nfc_tags.cfg`. A failed or malformed read
never overwrites the previous save. Successful explicit relabelling removes
obsolete mappings without removing unrelated settings or unbound shades.
The Android preset's user directory remains `DeskCanSaw Games/LaZer NFC`.
Selecting a game with `--game` alone uses the source project's usual profile.

The reader stops on pause, app backgrounding, results and navigation. A lost
adapter pauses the experiment and exposes fallback controls. Resume restores
the current recall window in full; delayed pre-pause callbacks cannot answer
a new robot. A per-UID debounce rejects jitter without suppressing a different
tag. Estimated RF latency is an age, never an Android timestamp compared
directly with Godot's paused clock.

Build the game-local Android plugin and Godot's Gradle template before using
the **Android - LaZer NFC** preset. See [`android/README.md`](android/README.md)
for the native toolchain, AAR and export requirements. Hardware behaviour
still requires a physical NFC phone; desktop fallback is not a hardware test.

## Presentation and accessibility

The game owns its 3D tabletop diorama inside an isolated, non-interactive
SubViewport. The shell and the colour deck remain native-resolution 2D.
Warm lighting, friendly robots, laser pops and clean-sweep celebrations take
inspiration from Chicken Pit's tactile toy aesthetic, without importing its
farm assets or changing the Compatibility renderer.

Reduced motion freezes decorative movement and suppresses camera/particle
flourishes. Disabling intense effects separately removes flashes and shake.
Captions accompany meaningful sounds; persistent on-screen phase, shape,
deadline and feedback text still work with sound off. Voice and haptics can be
disabled independently. Neither correctness nor movement depends on colour
alone.

## Code and authoring

| Path | Responsibility |
| --- | --- |
| `game.gd`, `lazer_nfc_options.gd` | Manifest, branding, stable options and key bindings |
| `gameplay.gd`, `gameplay.tscn` | Inherited shell, input lifecycle, tag setup and result mapping |
| `run/` | Pure palette, seeded sequences, recall rules and merged tag persistence |
| `input/`, `android/` | Keyboard, motion and actual native NFC reader |
| `arena/`, `ui/` | Read-only toy lab, native controls and shared-card art |
| `audio/`, `assets/audio/` | Scene-owned audio/haptics and original baked PCM |
| `tools/` | Offline audio, printable labels, cover and tutorial authoring |
| `tests/` | Pure-rule, input, persistence, scene and graphical regressions |

The model advances through scheduled boundaries with an explicit unpaused
clock. Physical tag binding is scene setup, not a model state that would wait
for a clock the shell has not started. Answer resolution is atomic; the
half-second recall gap prevents one input from hitting two robots. The arena
receives a public snapshot with no future answer during recall.

Rebuild original assets from this folder:

```powershell
python tools\bake_colors.py
godot --headless --path ..\.. --script res://games/lazer_nfc/tools/render_tags.gd -- --game=all
```

The bank contains 154 WAVs, including 21 colour instruments, playful cues,
laboratory music and spoken prompts. `bake_colors.py` uses Python's standard
library; `--check` regenerates the mathematical sounds in memory for comparison.

Spoken prompts are original text rendered offline with **Microsoft Zira Desktop**,
not a human recording or custom-trained voice. `tools/bake_voice.ps1`, run with
Windows PowerShell, renders them without a network service. The runtime uses
baked clips instead of depending on Android TTS latency. Game music and loops
pause and free with the scene and obey the shared Music/SFX sliders. The final
motif and score announcement continue over results; replay or leaving cancels
them rather than carrying old speech into another experiment.

The host tutorial recorder discovers `tools/tutorial_driver.gd`. Its shipped
36-second clip plays a
seeded keyboard experiment and demonstrates a mistake followed by a real
correction, rather than inventing a score. From `godot-base`:

```powershell
.\tools\record_tutorials.ps1 -Games lazer_nfc -Godot (Get-Command godot).Source
```

## Regressions

Run the game-local scripts sequentially from this folder:

```powershell
godot --headless --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_run_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_options_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_input_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_bindings_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_audio_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_scene_test.gd -- --game=all
godot --headless --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_intro_test.gd -- --game=all
godot --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_view_test.gd -- --game=all
godot --path ..\.. --script res://games/lazer_nfc/tests/lazer_nfc_layout_test.gd -- --game=all
```

The last two commands need a graphics display. Their optional
`--lazer-capture-dir=<absolute path>` saves landscape, portrait, ultrawide,
shade-mode and result captures; the full-scene suite also exercises enlarged
phone controls. The scene fixture intercepts achievement
writes; tests that change settings restore them. Framework catalog-driven
shell, options, lives, standalone, picker, instructions and sharing coverage
also includes this game automatically.

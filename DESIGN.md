# LaZer NFC — Game Design Document

> **Status:** implemented as a registered game folder. The run model, shell
> integration, toy laboratory, keyboard/touch play and native NFC source live
> here. Android packaging and physical-device requirements are documented in
> `android/README.md`; desktop play does not require NFC.
> **Target engine:** Godot 4.7, `gl_compatibility` renderer, as a game folder
> inside the existing `dcs_games` base project.
> **Location:** `dcs_games/godot-base/games/lazer_nfc/`, discovered by
> `GameCatalog` at startup beside `triangle_rush`, `desk_can_saw`,
> `dead_metal_jam`, `chicken_pit` and `anti_chess`.
> **Primary target:** Android phone with NFC. Desktop is a first-class
> development and fallback target, not an afterthought — every rule below has a
> keyboard path.
> **This document covers gameplay, input and presentation only.** Menus,
> settings, boot flow, pause, results, share cards, achievements, credits and
> accessibility already exist in the base and are *consumed*, not rebuilt.
> **Headline decision:** the run is a `GameShell` round. Earlier drafts of this
> spec described a standalone one-scene app with zero autoloads and its own
> HUD, pause and persistence. That app cannot ship from this repository, so
> every one of those pieces is re-seated on a framework seam in §1 and §2.
> **Framework cost:** one generic archive-discovery guard. No new autoload,
> no new `GameShell` hook and no
> `if game_id == "lazer_nfc"` anywhere under `autoload/`, `scenes/` or `ui/`.
> The two capabilities this game leans on — `CONTROL_STYLE_CUSTOM_KEYS` and
> `uses_shell_round_rules = false` — already exist for Chicken Pit and
> Anti-Chess.

### Implementation notes

- The catalog ignores `_`- and `.`-prefixed game directories. An archived
  manifest can no longer win discovery ahead of the live game with the same
  id. The archived directory remains untouched.
- The deliberately modest 2D arena in the draft became an original **3D toy
  laboratory** in a Compatibility-renderer SubViewport, inspired by Chicken
  Pit's warm handmade look. The inherited shell and responsive input deck
  remain native-resolution 2D. No farm asset or archived game code is imported.
- READY now includes **Learn the sounds**. Keys and touch preview instruments
  without marking the experiment Assisted. Start/confirm begins the real run;
  physical tags also retain the eyes-free start path.
- Binding is a **scene-owned setup phase after the shell activates**, not a
  model state waiting for a clock that has not started. Hardware-free play
  skips UID binding altogether; no synthetic keyboard UID is persisted.
- Answer resolution is atomic, with a separate half-second `RECALL_GAP`.
  The pure model processes crossed time boundaries and guards each window
  against early, stale and late input. An escape on the last robot advances
  without awarding a clear bonus.
- The double GO cue coincides with opening the first recall window, after
  the show-end rest. Reacting immediately to the cue is a valid answer,
  not an accidental "not yet".
- At the twelve-robot cap, the oldest note drops away and a new ending is
  appended. The learned suffix remains useful, but expert play cannot farm
  an unchanged melody forever.
- All **21 instruments** ship. The touch deck uses seven stable hue buttons
  plus Dark/Base/Light selectors rather than a cramped grid of 21 buttons.
  Holding both keyboard shade actions selects the base shade.
- A double-tag shortcut waits briefly on its first scan, and requires the
  **same UID** twice; the first red tap cannot both start a run immediately
  and remain eligible for a READY-only double tap.
- The shared result controls are retained, stacked on narrow screens and
  placed in a scroll container. A long report never requires a second HUD.
- Audio, spoken prompts and printable labels have offline authoring sources.
  The host's generic external tutorial-driver hook records a real seeded run.
  `README.md` lists the source files and current commands; the snippets below
  explain design intent rather than replacing those implementations.

---

## 0. Vocabulary

The word "round" means two different things in a memory game hosted by an
arcade shell, so this document fixes them apart and never mixes them:

| Term | Meaning | Owner |
| --- | --- | --- |
| **run** | One life pool from the first sequence to the last mistake. This is what `GameShell` calls a *round*: `_start_round()` opens it, `_end_round()` settles it into the results panel, **Play Again** starts the next one. | shell |
| **round** | One show-then-recall cycle inside a run. Round 1 is three colours; each round adds one. Many rounds happen inside one run. | game |
| **enemy** | One entry in the shown sequence, recalled against a per-enemy deadline. | game |
| **tag** | A physical NFC sticker bound to one colour. | player |

---

## 1. Where this game stops and the base begins

This is the most important table in the document. Everything on the left
already exists and is consumed as-is; anything the game re-implements from the
left column is a bug in this design, not a feature.

| The base already owns | The game owns |
| --- | --- |
| Studio sting, intro handoff, main menu, game picker, instructions, credits | The gameplay scene and everything inside `%Playfield` |
| Pause overlay (`Esc` / pad Back / touch button), `get_tree().paused` | Suspending the NFC reader and its own clock while paused |
| Countdown/lives HUD, score and streak labels, results and stats panels | What those numbers *mean*: score, combo, accuracy, lives left |
| Share card, QR, PNG save/open (`ShareManager`) | The share art variant and the payload fields it fills |
| Achievement registry, toasts, `user://achievements.cfg` | Which achievements exist and when they unlock |
| Settings storage, clamping and screen rows (`Settings`) | Which tunables and key bindings exist, and what they do |
| Volume buses, UI sounds, audio captions (`AudioManager`) | Colour notes, cues, haptics and their caption text |
| Scene transitions and fades (`Router`) | Nothing — the game never calls `change_scene_to_file()` |
| Player count, controller assignment (`GameSession`) | Nothing — this game is solo only |
| Theme, background and plaque in a standalone build (`GameTheme`) | Its own `GameTheme` values |

### 1.1 Decisions the framework changed

Every row here was decided differently in the pre-framework draft. The
right-hand column is why the framework's answer wins.

| Was | Now | Why |
| --- | --- | --- |
| `main.tscn`, one scene, boots straight into play | `gameplay.tscn`, an **inherited scene** of `res://scenes/game/game_shell.tscn` | The boot chain is `studio_logo → intro → main menu → Play`. A `run/main_scene` override would skip Settings, the theme and the pause overlay, and `Router` — not the project setting — owns every transition after boot. |
| "Zero autoloads" | Six autoloads, already loaded, in a fixed order | They are the product. Re-implementing volume, captions, saving and sharing inside the game would produce a second, worse copy of each. |
| `round_config.tres`, a game-private `RoundConfig` resource | `lazer_nfc_options.gd` constants + `GameManifest.tunables` | Values a player should be able to change belong on the Settings → Game tab, where `Settings` stores, clamps, formats and restores them. Values a player should not change are `const` in the options file. Nothing is tuned by editing a `.tres` in a shipped build. |
| Roll call binds tags; game invents its own JSON file | `user://lazer_nfc_tags.cfg`, a `ConfigFile` that **merges** on save | House rule: saves merge, never rebuild, so a shared `user://` is not truncated by a build that ships fewer games. `ConfigFile` is what `Settings` and `AchievementManager` use. |
| Own pause state (`PAUSED` in the state machine) | The shell's pause overlay | One pause UI for the whole product. The game only reacts: reader off, clock frozen, current window reissued on resume. |
| Own HUD labels, own results/score screen | `%TimeLabel`, `%TimeProgress`, `%Callout`, `%Hint`, the results and stats panels | A second scoreboard would drift from the share card, which reads the shell's numbers. |
| Lives, timers and score are private to `RoundController` | A **node-free run model** the scene drives, feeding `_scores`, `_streaks` and `_round_totals()` | Headless `SceneTree` tests can load a node-free model before autoloads exist; they cannot load a scene that touches `Settings`. |
| Timing from `Time.get_ticks_msec()` | An **explicit model clock** accumulated in `_update_round(delta)` | `get_tree().paused` stops `_process`, but wall-clock time keeps running. A 20-second pause must not close a 4-second window. Latency compensation still uses wall-clock deltas (§6.3) because that is what it measures. |
| IDLE screen with spoken gestures as the only "menu" | Settings → Game and Settings → Controls, plus the same gestures as *shortcuts that write those same keys* | The game has a menu now; pretending it does not would hide options from every player who is looking at the screen. The gestures stay because the design goal — playable with the screen face-down — is unchanged. |
| Portrait lock as a design rule | Portrait lock as a **standalone Android preset override**, on a layout that still survives resize | The project requires portrait-phone-through-ultrawide layouts. The shell HUD already does this; the arena must too (`_playfield_bounds()`). |

### 1.2 Folder layout

```
games/lazer_nfc/
  game.gd                  # manifest: identity, copy, achievements, credits, theme
  lazer_nfc_options.gd     # constants only: setting keys, ranges, bindings
  gameplay.gd / .tscn      # extends GameShell; inherited scene
  intro.tscn              # inherited, skippable opening + physical setup briefing
  run/run_state.gd         # node-free model: states, windows, lives, scoring
  run/sequence.gd          # seeded sequence generation
  run/palette.gd           # colours, shades, icons, notes
  run/tag_bindings.gd      # UID -> color_id map, roll call, ConfigFile merge
  input/nfc_source.gd      # Android plugin bridge, debounce, latency comp
  input/key_source.gd      # declared bindings and shade modifiers
  input/motion_source.gd   # accelerometer magnitude (momentum bonus only)
  arena/arena.gd / .tscn   # toy lab, concealed robots, deadline bar and laser pops
  audio/audio_director.gd  # colour notes, cues, ticks; SFX/Music buses only
  audio/haptics.gd         # named vibration patterns
  ui/share_art.gd / .tscn  # scorecard art
  ui/control_deck.gd       # native-resolution practice/setup/touch controls
  ui/shape_glyph.gd        # shared outlines for the lab, deck and print sheet
  ui/menu_*.tres           # standalone menu skin, background, plaque
  assets/                  # baked colour samples, icons, logo
  android/                 # game-owned Godot v2 plugin (AAR + export plugin)
  tools/bake_colors.py     # original offline PCM instrument/cue authoring
  tools/bake_voice.ps1     # offline local speech, no runtime TTS dependency
  tools/render_tags.gd     # printable labels from the live palette/glyphs
  tools/tutorial_driver.gd # real-input driver for the host recorder
  tests/                   # headless SceneTree regressions
```

---

## 2. Shell integration

### 2.1 Manifest

`game.gd` returns a `GameManifest`; nothing in the framework refers to this
game by name.

```gdscript
extends RefCounted

const OPTIONS := preload("res://games/lazer_nfc/lazer_nfc_options.gd")
const GAME_ID := OPTIONS.GAME_ID


static func manifest() -> GameManifest:
	var game := GameManifest.new()
	game.id = GAME_ID                       # "lazer_nfc" — never changes
	game.title = "LaZer NFC"
	game.tagline = "Little robots. Big memory. One more experiment."
	game.menu_order = 5
	game.gameplay_scene_path = "res://games/lazer_nfc/gameplay.tscn"
	game.intro_scene_path = "res://games/lazer_nfc/intro.tscn"
	game.share_art_scene_path = "res://games/lazer_nfc/ui/share_art.tscn"
	game.share_art_style = GAME_ID
	game.stats_url = "https://deskcansaw.com/stats/lz"   # 31 bytes; limit is 42
	# One player, one phone, one set of tags on the wall. There is no second
	# seat to offer and nothing for a CPU to hold, so mode select never renders
	# a question with one answer.
	game.supports_single_player = true
	game.supports_multiplayer = false
	game.supports_cpu_opponent = false
	# The run is a life pool across growing memory rounds, not a 30-second
	# arcade round. Clearing this hides Timer/Lives, extra time, gameplay speed
	# and target size instead of showing options that do nothing here.
	game.uses_shell_round_rules = false
	game.default_lives_mode = false
	# Colour keys and shade keys, not highlighted targets and not a cursor.
	game.control_style = GameManifest.CONTROL_STYLE_CUSTOM_KEYS
	game.tunables = OPTIONS.TUNABLES
	game.control_bindings = OPTIONS.CONTROL_BINDINGS
	game.copy = { ... }                     # §2.4
	game.achievements = { ... }             # §5.4
	game.credits = [ ... ]
	game.theme = _theme()
	game.tutorial_video_path = "res://assets/video/tutorial_lazer_nfc.ogv"
	game.tutorial_poster_path = "res://assets/video/tutorial_lazer_nfc_poster.webp"
	return game
```

Notes that are contracts, not preferences:

- `id` is a save key, a `[share]` key and an export-preset key. Once a build
  ships, it never changes.
- `stats_url` must stay within `ShareQrCode.MAX_URL_BYTES` (42 UTF-8 bytes) or
  the QR stops scanning after the card is downscaled to 600×315. A project
  setting `share/stats_urls/lazer_nfc` overrides it per build.
- The walkthrough clip is host-owned (`res://assets/video/`) and recorded with
  `tools/record_tutorials.ps1`. NFC cannot be recorded on a desktop, so the
  clip shows the **keyboard fallback** playing a real run. Shipping no clip is
  a supported state — `instructions_video_test.gd` checks that the screen falls
  back to text — but a declared clip must have a poster beside it.

### 2.2 `GameShell` hooks

`gameplay.gd` extends `GameShell` and overrides only these. Everything else —
pause, results, stats, share, confetti, screen shake, accessibility plumbing —
is inherited untouched.

| Hook | LaZer NFC uses it to |
| --- | --- |
| `game_id()` | Return `"lazer_nfc"`. Required; the shell resolves the manifest from it. |
| `_load_round_settings()` | `super()`, then read every `Settings.tunable*` in §4 into the model's config struct. Called on every `_start_round()`, so a slider moved mid-run only takes effect on the next run. |
| `_prepare_session()` | `super()`, then decide the input sources: NFC if the plugin reports an enabled adapter, keys/touch otherwise. |
| `_build_playfield()` | Instantiate `arena.tscn` under `%Playfield`, build the native control deck, and connect the scene-owned input/audio sources. |
| `_begin_first_round()` | Inherited: wait for the Router fade, then start the shell run. Binding, when needed, happens during the active setup phase. |
| `_reset_round_state()` | Reset the model: round 1, full lives, empty combo, clock zero. |
| `_activate_round()` | Enter the scene's tag roll call if needed; otherwise enter `READY` and offer sound practice and Start instead of the shell's "GO!". |
| `_update_round(delta, _time_left)` | Advance the model clock by `delta` and drain its event queue (§2.3). This is the only place model time moves. |
| `_handle_gameplay_input(event)` | Resolve declared keys through `KeySource` and submit colour answers. Touch buttons use the same `_submit_answer` seam. `pause` is already consumed by the shell. |
| `_finish_round()` | Stop the reader and hide the deck. Genuine completion retains its terminal cue/score speech over results; leaving cancels everything. Called on both paths, so it is not proof of a completed run. |
| `_describe_round_outcome(one, _two)` | "RUN OVER — reached round N" plus the score, in the game's own words. |
| `_round_totals()` | `{"hits": hits, "attempts": hits + wrongs + timeouts}` so the shell's accuracy figure and the share card agree with the run. |
| `_player_stats(0)` | Score, hits, misses (`wrongs + timeouts`), accuracy, best combo. |
| `_round_highlight_summary()` | Deepest round, best combo, assisted flag. |
| `_round_mode_summary()` | "Memory run · 7 tags · shades on" for the scorecard's mode line. |
| `_reset_round_gauge()` | Re-label the timer card as `BATTERIES LEFT` with the game's own pool, because `uses_shell_round_rules = false` otherwise parks it at `MATCH / --`. |
| `_award_round_achievements(one, _two)` | Unlock via `_unlock_round_achievement(id)`, guarded by genuine model completion, so the results panel and the card list them. |
| `_configure_mode_ui()` | `super()`, then adapt the inherited HUD and instructions for the laboratory. The deck reads live key labels. |
| `_on_controls_changed()` / `_on_player_labels_changed()` | Rebuild that copy the moment a key is rebound. |
| `_on_game_setting_changed(key, value)` | Apply the live-safe options immediately: haptics, voice, touch pad visibility. Difficulty options wait for the next run. |
| `_playfield_bounds()` | Report the arena rect so confetti and shake stay inside it in portrait. |
| `_share_payload()` | `super()`, then add rounds cleared and the assisted flag. |

Two shell helpers are deliberately **not** used: `_lose_life()` and
`_player_is_out()` no-op unless the shared lives mode is on, and this game
turned the shared round rules off. The run's life pool is the model's.

### 2.3 The run model

`run/run_state.gd` has no nodes, no input events, no `Settings` and no autoload
instances. The scene passes a config struct in, calls `advance(delta)` and
`answer(color_id, age_seconds)`, and drains a queue of events out. This is the
same rule Chicken Pit's `pit_state.gd` follows, and for the same reason: a
headless `SceneTree` test can load it before autoloads exist.

```gdscript
extends RefCounted

enum State { READY, ROUND_START, SHOWING, SHOW_END, AWAITING, RECALL_GAP, ROUND_WON, RUN_OVER }

var state := State.READY
var clock := 0.0              # seconds of *unpaused gameplay*, never wall clock
var round_n := 0
var lives := 0
var score := 0
var combo := 0
var hits := 0
var wrongs := 0
var timeouts := 0
var assisted := false


## Advances the model. `delta` comes from `_update_round`, so a paused tree
## freezes every window without the model knowing pause exists.
func advance(delta: float) -> void: ...


## `age_seconds` is how long ago the answer physically happened: NFC latency
## compensation, or 0.0 for a key press. The window is judged against
## `clock - age_seconds`, which is what makes a 1 ms-late scan deterministic.
func answer(
	color_id: StringName, age_seconds: float = 0.0,
	momentum: float = 0.0, assisted_input: bool = false
) -> bool: ...


## The scene consumes events once; snapshots never expose the hidden sequence.
func drain_events() -> Array[Dictionary]: ...
func snapshot() -> Dictionary: ...
```

The scene translates events into presentation and shell calls:

| Model event | Scene does |
| --- | --- |
| `round_started` | `%Callout` copy, sting, one haptic tick, caption |
| `note` | `AudioDirector.play_event()` and `Arena.react()` on the same frame; the following public snapshot supplies the visible cue |
| `go` | Snare cue, double haptic, caption "Recall now" |
| `awaiting` | `Arena.react()` and the concealed snapshot; deadline display and ticks start |
| `hit` | Laser, explosion, octave-up note, `_scores[0] = model.score`, `_update_scores()`, `_streaks[0] = model.combo`, `_update_streaks()` |
| `wrong` / `timeout` | Buzz or escape cue, rough haptic, life readout, `_flash_screen()` guarded by the intense-effects setting |
| `round_won` | Recap melody, `_show_announcement()`, confetti only if intense effects are on |
| `run_over` | `_end_round()` — the single door to the results panel |

`_end_round()` is called exactly once per run, from the `run_over` event.
Leaving the scene mid-run (Router fade, pause → main menu) reaches
`_finish_round()` only: an abandoned run is not a completed run and must not
record achievements or history.

### 2.4 Menu copy

`control_style = CONTROL_STYLE_CUSTOM_KEYS` means the shared menus render this
game's own action descriptions and append each action's **live** binding. The
manifest supplies wording, never literal key names:

- `single_player_description`, `solo_confirm_title`, `solo_confirm_description`
  — the setup step: "Seven tags on the wall, one phone in your hand."
- `instructions_headline` — "Remember the order. Go and touch it."
- `instructions_rules` — "Watch the sequence · Recall it one enemy at a time ·
  A wrong tag or a missed deadline costs a life · Esc pauses"
- `instructions_solo_summary` — the loop in three sentences, including that the
  screen is not needed.
- `instructions_player_one_controls` — what the colour and shade keys *do*, and
  that NFC replaces them on a phone. The menus append the current keycodes.
- `instructions_demo_prompt` — "TAP A TAG. FIRE THE LASER."

There are no `multiplayer_*` or `cpu_opponent_*` keys: with
`supports_multiplayer = false` those screens never render.

---

## 3. Core loop

### 3.1 One run, beat by beat

1. **Play** → `Router.start_selected_game()`. Mode select is skipped — a
   solo-only game with no `solo_setup_choices` has no question to ask — so the
   next screen is the instructions, or `gameplay.tscn` directly once the player
   turns `game/show_instructions` off.
2. **BINDING** — the tag roll call, only when it is due (§3.2).
3. **READY** — free sound practice, no model clock. Keys/touch preview notes;
   **Learn the sounds** makes NFC preview too. Start/confirm begins round 1.
   Outside practice, bound tags also start; gesture tags wait for a double scan.
4. **ROUND_START** (0.8 s) — round number announced (caption + voice + on-screen),
   rising two-note sting, one haptic tick. A grown palette is named: "Orange joins".
5. **SHOWING** (`seq_len × (show_time + show_gap)`) — the lead robot presents
   each cue with its colour and shape while playing its note. No
   answers accepted; a scan here plays the "not yet" cue.
6. **SHOW_END** (0.6 s) — a quiet rest. The double GO cue and haptic occur
   when the first recall window opens, not before input is accepted.
7. **Recall, one enemy at a time** — a grey silhouette with a shrinking deadline bar;
   metronome ticks accelerate across the window. The player physically moves
   and scans.
   - **Correct** → laser, explosion in the true colour, the note an octave up,
     one sharp haptic, points scored (§5.1).
   - **Wrong** → dissonant buzz, rough haptic, **one life**, combo reset. The
     enemy stays on its **original** deadline; the window is not extended.
   - **Timeout** → downward slide, three short haptics, one life, combo reset,
     the enemy escapes and the next one appears.
8. **ROUND_WON** — a celebratory fanfare, score is read out, one
   long soft haptic. The next round starts after 1.5 s with one more enemy.
9. **RUN_OVER** — lives reach 0 → descending fail motif, long rough haptic, and
   `_end_round()`. From here the shell owns the screen: results, stats,
   scorecard, **Play Again**, **Main Menu**.

Deterministic first-round timing (`seq_len = 3`, default window):

| Model time | Boundary |
| --- | --- |
| 0.0 s | Round announcement |
| 0.8 / 1.9 / 3.0 s | Notes 1 / 2 / 3 begin |
| 4.1 s | Last show gap ends; quiet show-end rest |
| 4.7 s | GO cue and first recall window open together |
| 8.7 s | Visible first-window deadline, if still unanswered |
| 8.85 s | Latest accepted compensated physical time |
| 8.93 s | Timeout dispatch, allowing delivery of an eligible scan |

Later windows depend on when the player answers. A correct hit or timeout
resolves once and leaves a half-second gap before the next robot.

### 3.2 When the roll call runs

Binding a tag means scanning it, so the roll call cannot live on a settings
screen. It is a phase of the gameplay scene, entered from `_activate_round()`
before the first memory sequence, with a usable NFC reader and only when due:

- fewer than three bound colours are stored, **or**
- shade mode was requested but no non-base shade is bound, **or**
- the player asked for it: the Settings → Game toggle
  `game/lz_rebind_tags`, **or** the double-scan gesture on the violet tag.

The game clears that toggle with `Settings.set_value(key, false)` once the roll
call completes, so it behaves like a one-shot request without inventing a
second place to store player intent.

Every prompt offers **Use keys / touch** as well as Skip. Without a usable
reader the scene enters READY directly with the full keyboard/touch palette.
It never makes a desktop player invent physical tags to get past setup.

The roll call itself: the game names a colour (voice + caption + on-screen),
the player scans the tag they want to be that colour, the UID is stored. Each
request times out after 12 s with a "skip" cue. Colours are requested in
palette-growth order (red, yellow, green, blue, orange, indigo, violet), so a
player with four tags gets exactly the four the early rounds use.

### 3.3 States and transitions

Pause is **not** a state here. The shell's overlay sets `get_tree().paused`,
which stops `_update_round`, which stops the model clock — the state machine
does not notice, which is exactly why it cannot get the resume wrong.

| From | To | Trigger |
| --- | --- | --- |
| — | `BINDING` (scene setup) | `_activate_round()`: usable NFC and fewer than three distinct hues bound, or rebind requested (§3.2) |
| — | `READY` | `_activate_round()` with enough tags bound |
| `BINDING` | `BINDING` (next colour) | A tag scanned that is not already bound, or the 12 s skip |
| `BINDING` | `READY` | Every colour processed and ≥ 3 bound |
| `READY` | `ROUND_START` | Start/`lz_confirm`, or a bound tag outside sound-practice mode; gesture tags wait briefly for a second scan |
| `ROUND_START` | `SHOWING` | 0.8 s of model time |
| `SHOWING` | `SHOW_END` | The last enemy's `show_time` elapsed |
| `SHOW_END` | `AWAITING` (k = 0) | 0.6 s |
| `AWAITING` | `RESOLVING` | An eligible answer arrives, or the compensated delivery deadline elapses |
| `RESOLVING` | `AWAITING` (same k) | Wrong, lives remaining — on the **original** deadline, not a new one |
| `RESOLVING` | `RECALL_GAP` then `AWAITING` (k + 1) | Correct, or a timeout with lives remaining, and k + 1 < `seq_len` |
| `RESOLVING` | `ROUND_WON` | Correct on the last enemy |
| `RESOLVING` | `RUN_OVER` | Lives reached 0 |
| `ROUND_WON` | `ROUND_START` | 1.5 s; round += 1, sequence += 1, palette grows on `PALETTE_GROWTH_ROUNDS` |
| `RUN_OVER` | — | The scene calls `_end_round()` once; the shell owns the screen from here |

`RESOLVING` denotes an atomic operation, not a state that accepts another
input. A timeout on the final robot also advances to the next round when lives
remain, without a clear bonus. Binding owns its own pausable scene clock;
`run_state.gd` starts at READY.

Rules the table does not show:

- Sequence length grows by one per round, capped at `SEQ_LEN_MAX`.
- At the cap, the oldest note drops and one fresh ending is appended.
- The palette grows on fixed rounds but never past the number of bound tags.
- Adjacent repeats are disallowed before round `ALLOW_REPEAT_FROM_ROUND`: a
  same-tag re-scan needs a lift-and-retap, which is a skill to introduce later.
- A correct answer is the exact `color_id`, hue *and* shade. Right hue, wrong
  shade is wrong — with its own near-miss cue, so the mistake teaches the map.

### 3.4 Tag gestures

Three gestures survive from the menu-less draft, because the design goal —
playable with the screen face-down — has not changed. Each one is now a
**shortcut that writes the setting the Game tab already owns**, so there is
exactly one source of truth and the screen and the wall can never disagree:

| Gesture (in `READY`) | Writes | Spoken and captioned as |
| --- | --- | --- |
| Double-scan **red** | `game/lz_shade_mode` toggled | "Shades on / off" |
| Double-scan **yellow** | `game/lz_touch_pad` toggled | "Touch pad shown / hidden" |
| Double-scan **violet** | `game/lz_rebind_tags` set, roll call restarted | "Rebinding tags" |

A double-scan is two reads of one UID at least `NFC_DEBOUNCE_MS` apart and at
most `DOUBLE_SCAN_MS` apart. Gestures are accepted only in `READY`, where no
window is open, so a gesture can never be mistaken for an answer. The same
choices remain available in Settings.

---

## 4. Options: what the player can change

All player-facing values are `GameManifest.tunables`, declared as constants in
`lazer_nfc_options.gd` and rendered by the framework on **Settings → Game**. In
a standalone build that tab sits on the main menu, so a player configures the
run before pressing Play; in a collection build it appears in the pause menu.

`lazer_nfc_options.gd` is **constants only** — no `Settings`, no autoload
instance, no `class_name` — because `game.gd` and the headless tests both
preload it before autoloads exist.

| Key | Type | Default | Range | Reads out as | Notes |
| --- | --- | --- | --- | --- | --- |
| `game/lz_lives` | slider | 3 | 1–5 | lives | The run's pool. The shared `game/starting_lives` row is hidden by `uses_shell_round_rules = false`. |
| `game/lz_scan_window` | slider | 4.0 | 2.0–6.0 | seconds | Per-enemy recall deadline at round 1. Below 2 s a 40 cm reach is not reliably scannable. |
| `game/lz_ramp` | choice | Standard | Gentle / Standard / Steep | — | Per-round tightening: window −0.1/−0.2/−0.3 s and show time −0.03/−0.05/−0.08 s, floored at `SCAN_WINDOW_MIN` / `SHOW_TIME_MIN`. One named knob instead of four sliders nobody can reason about. |
| `game/lz_start_length` | slider | 3 | 2–4 | count | Enemies in round 1. |
| `game/lz_palette_start` | slider | 4 | 3–7 | count | Active colours in round 1; capped by the number of bound tags. |
| `game/lz_shade_mode` | toggle | off | — | — | 21-tag advanced mode: three shades per hue. |
| `game/lz_touch_pad` | toggle | off | — | — | Always show the on-screen colour pad. It appears by itself when NFC is missing. Using it marks the run assisted (§5.1). |
| `game/lz_haptics` | slider | 1.0 | 0.0–1.0 | percent | Vibration strength; 0 disables it. |
| `game/lz_voice` | toggle | on | — | — | Spoken announcements. Independent of the shared audio-caption preference; persistent phase/shape/feedback text remains visible either way. |
| `game/lz_rebind_tags` | toggle | off | — | — | "Ask for my tags again at the next run." Cleared by the game once the roll call finishes. |

Everything else stays a `const` in the options file, because it tunes feel
rather than difficulty and a wrong value breaks the game rather than making it
easier:

| Constant | Value | Why it is not a setting |
| --- | --- | --- |
| `SEQ_LEN_MAX` | 12 | Beyond 12 a physical round runs over a minute. |
| `SHOW_TIME` / `SHOW_TIME_MIN` | 0.8 s / 0.5 s | Must stay ≥ the note duration. |
| `SHOW_GAP` | 0.3 s | Silence between shown enemies. |
| `SCAN_WINDOW_MIN` | 2.0 s | Hardware floor, not a difficulty choice. |
| `RECALL_GAP` | 0.5 s | Must be ≥ `NFC_DEBOUNCE_MS` so a legit repeat scan is not swallowed. |
| `GRACE_MS` | 150 | Accept scans this long after the window visibly closes. |
| `NFC_LATENCY_COMP_MS` | 80 | Added to callback age, then subtracted from the model's current clock for the physical-event comparison. |
| `NFC_DEBOUNCE_MS` | 500 | Same-UID suppression. |
| `PALETTE_GROWTH_ROUNDS` | `[3, 5, 7]` | Rounds at which one colour activates. |
| `ALLOW_REPEAT_FROM_ROUND` | 4 | A same-tag re-scan needs a lift-and-retap; that is a skill for later, not round 1. |
| `NOTE_DURATION` | 0.4 s | Baked into the samples. |
| `TICK_PERIOD_START/END` | 0.5 s → 0.12 s | Metronome ramp across a window. |
| `COMBO_STEP` / `COMBO_MAX` | 0.25 / 4.0 | Scoring shape. |
| `MOMENTUM_BONUS_MAX` / `MOMENTUM_ENERGY_FULL` | 0.5 / 25 m/s² | Bonus only (§7). |
| `DOUBLE_SCAN_MS` | 1500 | Gesture window. |
| `BINDING_TIMEOUT_S` | 12 | Roll-call skip. |

### 4.1 Controls

`control_bindings` are rendered on **Settings → Controls** and kept in sync with
the `InputMap`. A custom-key game inherits no target keys, no mouse actions and
no gamepad gameplay actions, so every key it needs is declared here.

| Key | Action | Default | Heading | Notes |
| --- | --- | --- | --- | --- |
| `controls/lz_color_1` … `_7` | `lz_color_1` … `lz_color_7` | `KEY_1` … `KEY_7` | Colour keys | Spectrum order: red, orange, yellow, green, blue, indigo, violet. |
| `controls/lz_shade_dark` | `lz_shade_dark` | `KEY_Q` | Shade keys | Held while a colour key is pressed → the dark shade. |
| `controls/lz_shade_light` | `lz_shade_light` | `KEY_E` | Shade keys | Held → the light shade. |
| `controls/lz_confirm` | `lz_confirm` | `KEY_SPACE` | Run | Starts the run from READY and skips a roll-call prompt. |

The keys are numbered in **spectrum** order while the palette activates in
**growth** order (§3.2), so the four colours of round 1 are keys 1, 3, 4 and 5.
That is deliberate: a key row that renumbers itself as the palette grows would
be unlearnable, and a palette that grows in spectrum order would hand the
player red-orange-yellow — three neighbouring hues — as the first thing they
must tell apart at 40 cm.

The shade keys are declared bindings rather than the `Shift`/`Ctrl` modifiers an
earlier draft used: `Settings.set_binding_key()` stores exactly one keycode per
row and validates conflicts inside one game, so a modifier combination is not
something the Controls tab can represent or a player can rebind. Conflicts are
scoped per game, so `1`–`7` here do not fight Triangle Rush's target keys.

None of these are marked `"movement": true` — nothing here steers anything, and
`Settings.movement_summary_for_game()` should not describe colour keys as
movement.

---

## 5. Scoring, lives and results

### 5.1 Points

```
per correct hit:
  base       = 100
  time_frac  = remaining_window / scan_window            # 0..1
  palette_f  = 1.0 + 0.15 * (active_base_hues - 4)       # 0.85 .. 1.45
  shade_f    = 1.5 if shade_mode else 1.0
  combo_mult = min(COMBO_MAX, 1.0 + combo * COMBO_STEP)  # combo = consecutive correct
  momentum   = 1.0 + MOMENTUM_BONUS_MAX * clamp(motion_energy / MOMENTUM_ENERGY_FULL, 0, 1)
  points     = round(base * (0.5 + 0.5 * time_frac) * palette_f * shade_f * combo_mult * momentum)
```

- **Combo** increments on a correct answer and resets on a wrong one or a
  timeout. It is mirrored into the shell's `_streaks[PLAYER_ONE]` /
  `_best_streaks[PLAYER_ONE]`, so `_best_combo_summary()`, the stats panel and
  the share card's combo field all read the same number for free.
- **Round bonus**: `50 × seq_len` on ROUND_WON, doubled when no life was lost
  that round.
- **Wrong**: −1 life, combo reset, no points, enemy stays on its original
  deadline.
- **Timeout**: −1 life, combo reset, no points, enemy escapes, advance.
- **Assisted**: if an eligible recall answer came from the touch pad, the run
  is flagged and its raw accumulated score is halved, rounding down. The
  reduction includes already banked points and never compounds. Practice,
  unknown colours and early taps do not mark assistance. There is no
  leaderboard; the flag is honesty, not punishment.

### 5.2 Ending a run

Lives reach 0 at any resolution → `RUN_OVER` → `_end_round()`. There is no
other exit: a timeout on the last enemy of a round with lives remaining ends
the round without a round bonus and starts the next one.

`_round_totals()` returns `{"hits": hits, "attempts": hits + wrongs + timeouts}`,
which is what feeds the shell's accuracy figure, the stats panel and the share
card — so accuracy on the scorecard is the same number the run computed.

### 5.3 The gauge

With `uses_shell_round_rules = false` the shell parks the timer card at
`MATCH / --`. This game overrides `_reset_round_gauge()` to show its own pool:
caption `BATTERIES LEFT`, label the count, `%TimeProgress` maximum set to the starting
lives. A numeral rather than colour-only pips, matching the shell's own lives
readout, so the HUD survives the player-labels and colour-blindness cases.

### 5.4 Achievements

Registered from the manifest, persisted by `AchievementManager` into
`user://achievements.cfg`, unlocked through `_unlock_round_achievement()` so
they reach the results panel, the toast and the scorecard. Keys are globally
unique and stable forever.

| Id | Title | Earned by |
| --- | --- | --- |
| `lazer_nfc_first_run` | First Contact | Finish a run. |
| `lazer_nfc_round_five` | Long Memory | Reach round 5 in one run. |
| `lazer_nfc_flawless_round` | Clean Sweep | Clear a round of six or more without losing a life. |
| `lazer_nfc_shade_run` | Full Spectrum | Finish a run with shade mode actually active. |
| `lazer_nfc_unassisted` | No Handrail | Reach round 4 without touching the fallback pad. |

Achievement and unlock flags never regress after a later, worse run.

---

## 6. NFC input

### 6.1 `NfcSource`

A scene-owned `Node` wrapping the native plugin. It emits canonical UIDs and
elapsed ages; `gameplay.gd` resolves them through `TagBindings` before calling
the one colour-answer seam.

| Surface | Contract |
| --- | --- |
| `tag_scanned(uid, age_ms)` | A lowercase hexadecimal UID and compensated elapsed age |
| `availability_changed(available, reason)` | Device availability, separate from reader activation |
| `reader_error(message)` | A real failure, surfaced to the player |
| `available()` | Whether a usable adapter exists |
| `start()` / `stop()` | Explicit game request; no reader runs merely because the node exists |
| `reset_debounce()` | Invalidate pending callbacks and drain them before reopening |

Connect the signals before adding the node to the tree, so the initial
availability notification is not lost. `no_plugin`, `no_hardware` and
`disabled` enter the real fallback, not a mock NFC stream.

Both native and GDScript layers invalidate callback generations on stop,
pause and scene exit. Debounce is per UID, including an A-B-A sequence.
Availability restoration reports a device change but never revives a revoked
reader request without an explicit `start()` from the scene.

`age_ms` rather than an absolute timestamp is the framework-shaped change: the
model's clock stops when the tree is paused, so an absolute wall-clock stamp is
not comparable to it. An age is.

### 6.2 The Android plugin

A **game-owned** Godot v2 Android plugin in `games/lazer_nfc/android/`: an AAR
plus an `EditorExportPlugin`, registered through the project's
`[editor_plugins]` list. It is not vendored third-party code, so it does not
live under `third_party/`.

Use `NfcAdapter.enableReaderMode`, not foreground dispatch:

- Foreground dispatch delivers tags as new Intents into the Activity
  (`onNewIntent`), which interacts badly with Godot's activity lifecycle and
  adds 100+ ms of intent dispatch latency. Reader mode is a direct callback.
- Reader mode takes `FLAG_READER_NO_PLATFORM_SOUNDS` (kills the system "ding",
  which would otherwise fight the game's audio) and `FLAG_READER_SKIP_NDEF_CHECK`
  (we only want the UID; skipping the NDEF read removes 30–80 ms).

The shipped implementation is Java, not the earlier illustrative Kotlin
prototype. Reader-mode calls run on the Activity UI thread; discoveries cross
to Godot's render thread with their captured generation. Activity resume
alone never enables scanning in a menu. Adapter broadcasts are registered and
unregistered with the native lifecycle.

The exact build and export contract lives in `android/README.md`, beside the
version-pinned Gradle wrapper and source. This avoids maintaining a second,
incomplete native implementation in the design document.

Manifest additions, merged from the plugin's AAR:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-feature android:name="android.hardware.nfc" android:required="false" />
```

No intent filter is needed for reader mode. `required="false"` keeps the APK
installable on NFC-less devices, which then land on the touch pad.

**Reader lifecycle is the game's job, not the plugin's alone.** The reader is
enabled only while a run is live: `_finish_round()`, the pause overlay opening
and `_exit_tree()` all disable it. A scene that left the tree must never
process a discovery.

### 6.3 Latency budget

| Stage | Typical | Budget |
| --- | --- | --- |
| Tag enters field → anticollision → `onTagDiscovered` | 40–120 ms | 120 ms |
| Binder thread → main thread (`call_deferred`, next frame at 60 fps) | ≤ 17 ms | 20 ms |
| `TagBindings` lookup + scene dispatch | < 1 ms | 5 ms |
| **Total** | ~80–140 ms | **≤ 150 ms** |

These are design budgets, not physical-device measurements. Native code adds
the **80 ms RF estimate once** when computing elapsed callback age. GDScript
adds only its own deferred queue time. A physical time is compared with the
current model window as `model.clock - age`.

Physical grace is **150 ms** beyond the visible deadline. Timeout dispatch
waits a further **80 ms** for delivery; that is not an extra 80 ms of physical
grace. Ages outside 0–230 ms and physical times before this window are
rejected. Android and Godot absolute clock epochs are never compared.

### 6.4 Debounce and duplicate reads

- Reader mode fires once per discovery. A tag held still does not re-fire; a
  tag jittering at the field edge re-fires every 100–250 ms. The 500 ms
  same-UID debounce covers jitter.
- Different UIDs are never debounced against each other: swinging past a wrong
  tag onto the right one within 500 ms must register the right one.
- Legit consecutive same-colour enemies (round ≥ 4) need a lift-and-retap;
  `RECALL_GAP` ≥ `NFC_DEBOUNCE_MS` guarantees the second tap is not swallowed.
- The double-scan gesture uses two reads of one UID that are ≥ debounce apart
  and ≤ `DOUBLE_SCAN_MS` apart.

### 6.5 Keyboard and touch

There is no separate "debug input": the fallback **is** the declared control
scheme of §4.1, which is why it appears on the Controls tab and in the
instructions like any other game's keys.

- Keys: `lz_color_1` … `lz_color_7`, plus the two shade keys. Available on
  every platform, always.
- Touch pad: a game-owned `Control` of seven colour + icon buttons and an
  optional Dark/Base/Light selector, shown
  when the device has no usable NFC or when `game/lz_touch_pad` is on, hidden
  while the results panel is up.
- Keyboard play bypasses physical UID setup. A key pressed during a hardware
  roll call selects the fallback path instead of writing a fake tag to disk.
- READY sound previews are free, regardless of the input device. Only touch
  answers submitted during a real recall window mark the run Assisted.
- Answers from the pad set the assisted flag; answers from keys do not. A
  keyboard is the desktop's real controller; the pad is a workaround on a
  phone that was supposed to make you walk.

---

## 7. Sensors

### 7.1 Verdicts

| Sensor | Idea | Fit | Godot/Android notes | Verdict |
| --- | --- | --- | --- | --- |
| Gyro/accel | Tilt-to-aim laser | Poor: the answer *is* the tag; aiming adds a second failure axis | `Input.get_gyroscope()` | **Cut** |
| Gyro/accel | Flick/slash to fire | Poor: the scan already is the fire; a gesture adds 200+ ms and misfires | threshold on high-passed accel | **Cut** |
| Gyro/accel | Reach motion as the answer | Cannot identify *which* tag | — | **Cut** |
| Gyro/accel | Shake to reload | Nothing to reload; a shake is also a reach | — | **Cut** |
| Gyro/accel | Reward measured motion | Turns tag spacing into a player-chosen difficulty dial | `Input.get_accelerometer()` minus `get_gravity()`, polled in `_update_round` | **MVP** as bonus-only Momentum |
| Magnetometer | Tags at compass headings | Indoor distortion puts headings 20–60° off; calibration needs a prompt there is no room for | `Input.get_magnetometer()`, raw µT | **Cut** |
| Camera | Read surface colour | Lighting-dependent; the phone must be held up, not pressed down | unreliable `CameraServer` on Android | **Cut** |
| Camera | QR/ArUco fallback | Works with no NFC, but changes the motion to a hover and needs a CV plugin | plugin | **Stretch** |
| Camera | AR overlay | The player's eyes are supposed to be off the screen | ARCore | **Cut** |
| Ambient light | Lights-out mode | The game is already eyes-free; darkness is the default, not a modifier | plugin | **Cut** |
| Proximity | "You're close" pre-cue | Good in theory; the sensor is top-front while the NFC antenna is top-back | plugin, per-device offset | **Stretch** |
| Microphone | Clap to fire | Latency > 150 ms, false triggers from the game's own audio | — | **Cut** |
| Microphone | Voice-naming the colour | Real value for limited mobility, but 300–800 ms recognition latency | `SpeechRecognizer` plugin | **Stretch** (accessibility) |
| Haptics | Per-event patterns | Primary non-visual confirmation | `Input.vibrate_handheld(ms, amplitude)` | **MVP** |
| Touchscreen | Fallback pad | A complete alternative to NFC or a keyboard | Shape-labelled `Button`s | **MVP** (§6.5) |

### 7.2 One answer seam

There is no `InputHub`, `AnswerSource` class hierarchy or second input
framework. `gameplay.gd` resolves native UIDs, key events and button signals
into `_submit_answer(color_id, source, age_ms)`. That method is also the free
READY-preview gate. Real recall goes to
`model.answer(color_id, age_ms / 1000.0, motion_peak, source == &"touch")`.

The node-free model therefore sees colour identities, elapsed age, bounded
motion and an assistance flag, never platform events or autoloads.

### 7.3 Momentum

```gdscript
# input/motion_source.gd — a ModifierSource, polled from _update_round
var _peak := 0.0

func sample() -> void:
	var linear := Input.get_accelerometer() - Input.get_gravity()   # m/s^2
	_peak = maxf(_peak, linear.length())

func take_peak() -> float:
	var peak := _peak
	_peak = 0.0
	return peak
```

Sensors return `Vector3.ZERO` off mobile, so the bonus is simply 1.0 on
desktop and nothing needs a platform branch. Sampling happens in
`_update_round`, which means it also freezes on pause. Enable only
`sensors/enable_accelerometer` and `sensors/enable_gravity` under the
`lazer_nfc` feature tag; gyroscope and magnetometer cost battery for nothing.

Nothing is gated on motion: a still player forgoes a bonus, never correctness.
Acceleration is not a measurement of distance. Keep tags comfortably reachable;
the game never asks the player to swing harder or stretch farther to succeed.

---

## 8. Audio

### 8.1 Pitch and timbre, argued

The game does not assume absolute pitch or require the player to name notes.
**Pitch and timbre work redundantly**: timbre is the
identity cue (people name "the bell" instantly), pitch is the ordering cue (the
sequence is a melody, and rising hue = rising pitch is a mnemonic). Mapping
hues onto a stacked triad rather than a stepwise scale gives the base colours
distinct pitch positions. Free READY practice teaches the mapping without
spending batteries or requiring musical terminology.

### 8.2 Colour → sound

| Colour | Icon | Note | MIDI | Timbre | Duration |
| --- | --- | --- | --- | --- | --- |
| Red | ▲ | C3 | 48 | Sub-square bass, 20 ms attack | 400 ms |
| Orange | ◆ | E3 | 52 | Saw brass, slight growl | 400 ms |
| Yellow | ★ | G3 | 55 | FM bell, bright attack | 400 ms |
| Green | ● | C4 | 60 | Plucked string (Karplus-Strong) | 400 ms |
| Blue | ■ | E4 | 64 | Sine flute, 5 Hz vibrato | 400 ms |
| Indigo | hexagon | G4 | 67 | Detuned pad / choir "oo" | 400 ms |
| Violet | ✚ | C5 | 72 | Glassy sine, long tail | 400 ms |

Shades (advanced mode) are encoded by **brightness first, semitone second**:
dark = low-passed at 2× the fundamental, −1 semitone, lengthened attack; light
= high-shelf +6 dB, +1 semitone, shortened attack. An octave shift was rejected
because it would move a shade out of its hue's pitch neighbourhood; a rhythmic marker was rejected
because it changes the tempo of the melody being memorised. A near miss (right
hue, wrong shade) plays the correct shade quietly after the buzz, so every
mistake teaches the mapping. Five shades per hue were rejected: three levels of
brightness are discriminable to an untrained listener, five are not.

### 8.3 Samples, not runtime synthesis

21 mono 44.1 kHz WAVs under `assets/audio/colors/{hue}_{shade}.wav`, baked
offline by `tools/bake_colors.py`, shipped with the WAVs.
Runtime `AudioStreamGenerator` synthesis was rejected: it needs a fill thread,
adds a buffer of latency and burns CPU during a physical game. Runtime filters
on buses were rejected because parameter changes glitch when two shades of one
hue play back to back. The octave-up confirm cue reuses the same sample at
`pitch_scale = 2.0`.

This matches the house rule the other games follow: author audio offline with a
committed script, never synthesise on the audio callback, and never extend the
shared procedural synthesiser in `audio_manager.gd` with game-specific sounds.

### 8.4 Buses

The earlier draft defined four custom buses (`Sequence`, `SFX`, `Riser`,
`Voice`). That is now **three shared buses**: `Master`, `Music`, `SFX`, the ones
`AudioManager` mixes and the Settings → Audio sliders control. A private bus
layout would silently ignore the player's volume settings.

| Layer | Route |
| --- | --- |
| Colour notes, ticks, hit/wrong/timeout cues, unbound beep | Scene-owned, preloaded players on the shared SFX bus |
| Riser (momentum) | one game-owned looping `AudioStreamPlayer` on the SFX bus, freed with the scene |
| Ambient READY pad | game-owned player on the Music bus, stopped on `_finish_round()` |
| Voice announcements | SFX bus, pre-recorded lines, ducked under nothing |
| Every meaningful cue | **also** `AudioManager.request_caption(text)` |

The model's event schedule drives sound and visuals together. The scene
delivers each event to the audio director and arena in the same frame, then
presents the public snapshot. Neither visual animation nor an audio-finished
callback advances the rules.

### 8.5 Feedback latency

Android output latency is typically 40–100 ms end to end; the game's own
overhead must stay under 10 ms. Preload every stream in `_ready()`, never
`load()` at play time, and call `play()` in the same frame the answer arrives
(never deferred). The `lazer_nfc` feature tag sets `audio/driver/mix_rate`
44100 and `audio/driver/output_latency` 15 ms. Haptics fire in the same frame
as the audio call; the motor's own 10–30 ms start latency is close enough to
audio that the two read as one event.

Voice lines, numbers and all colour/binding prompts are rendered offline with
local system speech by `tools/bake_voice.ps1`. There is no runtime TTS or
network service dependency, even in READY and binding. The first sequence
note cancels unfinished announcements rather than allowing speech to mask a
memory cue.

---

## 9. Feedback design

Hard requirement, unchanged by the framework: every state and transition must
be identifiable **with the screen face-down**. The proof is that each row below
has an audio *and* a haptic signature unique among the states it can occur in.
The framework adds a third channel, audio captions, while honouring the
player's caption preference. The game also keeps its phase, shapes, deadline
and result feedback on screen, so switching captions or sound off cannot
remove all visual information.

| Event / state | Audio | Haptic | Caption | Unique because |
| --- | --- | --- | --- | --- |
| READY | Slow 2 s breathing pad; voice every 10 s: "Tap any tag to start." | none | "Ready — tap any tag" | Only looping pad |
| Roll call request | Voice: "Red", then a soft ping every 2 s | none | "Scan the tag for red" | Only prompt-then-ping |
| Bound / skipped | The colour's note / low thud | one tick / none | "Red bound" | |
| ROUND_START | Two-note rising sting + "Round N" | 40 ms tick | "Round N" (+ "Orange joins") | Only voice inside a round |
| SHOWING | The melody, one note per enemy | 40 ms tick per note | "Showing 3 colours" | Only colour notes in series |
| First recall window opens | Snare burst + rising whoosh | double 40/40/40 ms | "Recall now" | Only double pulse; input is already accepted |
| AWAITING | Ticks accelerating 0.5 s → 0.12 s; riser swells with motion | none — silence on the wrist means "still waiting" | "Enemy 2 of 4" | Accelerating ticks exist nowhere else |
| Correct | The enemy's note an octave up over a laser zap | 60 ms sharp | "Hit — blue" | Only octave-up colour note |
| Wrong | 250 ms minor-second buzz (+ the true shade, quietly, on a near miss) | 3 × 40 ms + 200 ms rough | "Wrong — 2 lives left" | Only rough pattern |
| Timeout | 350 ms downward slide + escape whoosh | 3 × 40 ms spaced | "Escaped — 1 life left" | Only triple spaced short |
| Combo 5 / 10 / 20 | Rising arpeggio of 3 / 4 / 5 notes | 2 × 30 ms | "Combo x10" | |
| Scan during SHOWING | Muted "not yet" tock | 20 ms | "Not yet" | Softer than anything else |
| Unbound tag | Flat 200 ms sine, outside the triad | 100 ms medium | "Unknown tag" | Only pitch outside the scale |
| ROUND_WON | Fanfare and a spoken round/score announcement | 400 ms soft | "Round N cleared" | Only long soft |
| RUN_OVER | Descending fail motif, score, accuracy, "assisted" | 600 ms rough | "Run over" | Only long rough |
| NFC lost | Voice "NFC off", then silence | none | "NFC unavailable — touch pad shown" | Only silence + voice |

Eyes-free walkthrough: pad → tap → sting + "Round 1" → three notes (memorise) →
double pulse (go) → ticks (move) → octave-up C3 + sharp tap (got red) → gap →
ticks → buzz + rough + two taps (wrong, two lives) → ticks continue (same
enemy) → octave-up C4 → … → fanfare + "Round 1. 320." The screen is never
needed.

Haptic patterns are arrays of `[on_ms, off_ms, …]` played by chaining
`Input.vibrate_handheld`, scaled by `game/lz_haptics` and skipped entirely at 0.
The pause overlay stops the pattern chain, because a vibration that outlives
its cause is a bug.

---

## 10. Presentation

The arena is an original **3D tabletop toy laboratory**, mounted under
`%Playfield` in an isolated, non-interactive SubViewport. Friendly robots,
a chunky turret, warm lighting and playful laser/pop reactions make a clean
recall satisfying to watch as well as hear. The look takes inspiration from
Chicken Pit's handmade toys, not its farm models. The screen can still be
ignored during an NFC run: feedback remains redundant.

The colour deck stays at native 2D resolution outside the 3D render surface.
Its stable shape-labelled buttons, live bindings and optional shade selectors
reflow for portrait and ultrawide. The shell's real result/stat controls stack
and scroll on narrow screens rather than being replaced with a separate HUD.

An enemy carries three redundant channels: colour, a high-contrast shape
and sound. The canonical shapes are triangle, diamond, star, circle,
square, hexagon and plus. Shade mode uses Dark/Base/Light names and a dot count
(1–3), matching the printed tags. During recall the silhouette is grey and carries **no** answer icon: showing it
would remove the memory component that is the whole game.

Two framework rules bind the arena:

- **Layout.** `_playfield_bounds()` reports the arena rect, and the lane
  reflows from `_on_layout_changed`-equivalent resizes. Animate with `modulate`
  and `scale` around a centred `pivot_offset`, never `position`, which bakes
  offsets and breaks on the next resize. The standalone Android preset locks
  portrait, but the scene must still survive a desktop window drag.
- **Renderer.** `gl_compatibility`, with no Forward+/Vulkan-only feature,
  screen-space effect or compute. The viewport owns its world, disables GUI
  input and stretches with its container; it never steals taps from the deck.

---

## 11. Edge cases

| Case | Behaviour |
| --- | --- |
| Unbound tag during recall | "Unbound" cue, no penalty, window keeps running. In READY: cue plus "Unknown tag — double-tap violet to rebind." |
| Scan during SHOWING / SHOW_END / ROUND_START | "Not yet" cue, no penalty, does not skip the show. |
| Two tags too close | The radio chooses a discovered tag; software cannot infer physical spacing from two callback times. The setup briefing and printed sheet recommend at least 15 cm separation. |
| NFC disabled mid-run | `adapter_state(false)` → open the pause overlay, caption it, show the touch pad. Re-enabling resumes with a **fresh** window for the current enemy. |
| App backgrounded | `NOTIFICATION_APPLICATION_PAUSED` → `open_pause_menu()`. The plugin's own lifecycle disables the reader; the model clock stops because `_update_round` stops. On resume the current enemy's window is reissued in full — the player's hand is not where it was. |
| Player pauses deliberately | Identical path. There is no game-owned pause state; `_on_pause_closed()` reissues the window. |
| Scan 1 ms after the window closes | Judged from `clock - age`, with `GRACE_MS` and `NFC_LATENCY_COMP_MS` folded in: accepted. A compensated answer more than 150 ms past the window is a timeout even if the model has not yet reached the deadline. |
| Answer arriving in `RESOLVING` | Dropped. Resolution is atomic. |
| Frame hitch or thermal throttle | The model integrates `delta`, so a 200 ms hitch consumes 200 ms of window and no more. Windows are never frame-counted. |
| Accelerometer unavailable | Momentum multiplier is 1.0 and the riser stays flat. No message: it is a bonus. |
| Fewer than three bound tags | Stay in the roll call: "Need at least three tags." Restart the request loop. |
| Fewer tags than colours | `palette_max = bound_count`. With four tags the palette never grows and the ramp comes from length and window only. |
| Reader error | Surface the native error and offer fallback. Mere inactivity is not proof that another app owns the reader. |
| Player leaves mid-run | `_finish_round()` only: reader off, audio stopped, no `_end_round()`, no achievements, no scorecard. An abandoned run is not a run. |
| Headless test run | No plugin, no sensors, no audio device. Every source degrades to "unavailable" and the keyboard source answers, so `game_shell_test.gd` can drive a full run. |
| Window resize / rotation | The HUD is the shell's and already responsive; the arena reflows from `_playfield_bounds()`. |

---

## 12. Accessibility

The framework settings are honoured, not re-invented:

- **Reduced motion** (`Settings.reduced_motion_enabled()`): ambient motion,
  bounces, sprinkles and camera shake stop. The deadline bar still changes,
  because remaining time is essential information rather than decoration.
- **Intense visual effects** (`Settings.visual_effects_enabled()`): the wrong/
  timeout screen flash and shake are suppressed. Audio and haptics are not,
  so no information is lost.
- **Audio captions** (`Settings.audio_captions_enabled()`): every row of §9 has
  caption text. This game is sound-first, so a caption is written for every
  meaningful event before the sound is.
- **Player labels**: solo only, so the shell's P1 card is all there is; nothing
  encodes meaning in colour alone.
- **Live changes**: `_on_game_setting_changed()` applies haptics, voice and the
  touch pad immediately; difficulty options wait for the next run, which is why
  they are read in `_load_round_settings()`.

Game-specific accessibility, beyond the framework:

- **Colour vision.** Three redundant channels per enemy (colour, icon, sound)
  and the same three on the printed tags. The first palette includes both red
  and green, so shape and timbre are essential from the first round, not just
  an option for later palettes.
- **Low vision / no vision.** §9 is the design; the acceptance test is a tester
  with the screen covered completing three rounds. Printed tags should emboss
  the dot count so a tag can be identified by touch.
- **Limited mobility.** Tags may be placed inside one comfortable reachable
  arc, observing the 15 cm separation guidance and forgoing only the momentum
  bonus. The roll call never enforces spacing. `game/lz_scan_window` reaches
  6 s and `game/lz_ramp` has a Gentle setting; between them a run can be as
  slow as a player needs without a separate "relaxed mode" resource.
- **Voice naming** the colour is the stretch path (§7.1); if built, it is
  another producer for the same colour-answer seam with an appropriate window,
  not a new game mode.

---

## 13. Physical setup

**Tags.** Seven NTAG213/215 stickers (13.56 MHz, ISO 14443-A) on coloured
cardstock squares (~6 × 6 cm), or pre-coloured NFC fobs. Any Android-readable
tag works; the game uses the UID only, never an NDEF payload. Shade mode wants
21.

**Placement** (spoken during the roll call, printed on the intro's setup card):

- Place tags on a stable board or nearby surfaces, comfortably within reach.
  Neither standing nor a minimum reach distance is required.
- Never two tags closer than **15 cm** — the NFC field is 3–4 cm, and 15 cm
  eliminates cross-reads when swinging past.
- Non-metallic surfaces only; metal behind a tag kills the read. Use
  ferrite-backed "on-metal" tags where it is unavoidable.
- Locate the particular phone's antenna during setup; it is often near the
  upper back, but placement and read orientation vary by device and tag.

**Labelling.**

| Mode | Physical label |
| --- | --- |
| Base | Solid colour square + the colour's icon printed large in black + the colour name |
| Shade | Hue tint, the same shape, a dot count (one/two/three), and the literal name ("Dark blue", "Blue", "Light blue") |

Two redundant non-colour markers, so shades are distinguishable at a glance
from a metre away and the dot count is readable by touch if embossed. The print
sheet is one A4 page of 21 rectangular labels with cut lines, shipped beside
the game. It is generated from the same palette and shape outlines as the UI;
the printed labels themselves contain no NFC hardware.

**Persistence.** `user://lazer_nfc_tags.cfg`, a `ConfigFile` of
`uid → color_id`, loaded once and **merged** on save: a failed read never
overwrites a good file, and a build that ships fewer colours never truncates
one that shipped more. `application/config/custom_user_dir_name.lazer_nfc`
("DeskCanSaw Games/LaZer NFC") names the folder those bindings live in and must
stay stable forever — changing it strands every player's tags.

---

## 14. Build configuration

### 14.1 Project settings the game owns

The platform overrides use the `lazer_nfc` feature tag. The editor plugin is
registered globally but adds its native library only to LaZer NFC Android
exports; it does not enable a reader in other games. The stats URL is also
declared in the manifest and can be overridden per project:

| Setting | Value | Why |
| --- | --- | --- |
| `application/config/name.lazer_nfc` | `LaZer NFC` | Standalone product name |
| `application/config/custom_user_dir_name.lazer_nfc` | `DeskCanSaw Games/LaZer NFC` | Stable forever |
| `dcs/build/single_game_id.lazer_nfc` | `lazer_nfc` | Pins the preset to this game |
| `display/window/size/viewport_*.lazer_nfc` | 720 × 1280 | Portrait design resolution |
| `display/window/size/window_*_override.lazer_nfc` | 540 × 960 | Desktop preview window while developing |
| `display/window/handheld/orientation.lazer_nfc` | `1` (portrait) | Phone build only |
| `audio/driver/mix_rate.lazer_nfc` | 44100 | §8.5 |
| `audio/driver/output_latency.lazer_nfc` | 15 | §8.5 |
| `audio/driver/enable_input.lazer_nfc` | false | No microphone; the base enables it for Dead Metal Jam |
| `input_devices/sensors/enable_accelerometer.lazer_nfc` | true | Momentum |
| `input_devices/sensors/enable_gravity.lazer_nfc` | true | Momentum |
| `input_devices/sensors/enable_gyroscope/magnetometer.lazer_nfc` | false | Battery for nothing |
| `share/stats_urls/lazer_nfc` | `https://deskcansaw.com/stats/lz` | QR target, ≤ 42 bytes. Optional — the manifest already carries it |
| `editor_plugins/enabled` | includes `res://games/lazer_nfc/android/plugin.cfg` | Ships the AAR with the Android export |

**`run/main_scene.lazer_nfc` has been removed.** The APK follows the same
`res://scenes/boot/studio_logo.tscn` boot as every other build, and reaches
the game through its briefing, main menu and `Router`. The archive is excluded
from exports, and other standalone presets exclude the new game folder.

### 14.2 Standalone build

```powershell
godot --path . -- --game=lazer_nfc      # run the standalone from source
godot --path . -- --game=all            # the collection, with the picker
```

Launchers may instead set the process-local `DCS_GAME` environment variable.
Source selection pins the catalog; the named Android preset additionally
applies the portrait, audio and stable-user-directory feature overrides.

The export preset **Android — LaZer NFC** carries `custom_features="lazer_nfc"`
and needs Godot's Gradle build enabled so the plugin AAR is packaged. Because
the catalog then holds exactly one game, the framework does the rest for free:

- the title screen takes its name and tagline from the manifest;
- the Play button starts the game directly, with no picker;
- `intro.tscn` replaces the framework intro (and is the natural place for the
  tag-placement briefing, which no other game needs);
- the manifest's `credits` lead the credits roll;
- the manifest's `GameTheme` dresses every screen;
- **Controls** and **Game** sit on the main menu, so tags, keys and difficulty
  are configurable before the first run.

---

## 15. Tests

Standalone headless `SceneTree` scripts, run one at a time, each exiting 0.
Framework tests share `user://`, so run them sequentially and restore anything
they change.

Game-owned, in `games/lazer_nfc/tests/`:

```bash
godot --headless --path . --script res://games/lazer_nfc/tests/lazer_nfc_options_test.gd -- --game=all
godot --headless --path . --script res://games/lazer_nfc/tests/lazer_nfc_run_test.gd -- --game=all
godot --headless --path . --script res://games/lazer_nfc/tests/lazer_nfc_input_test.gd -- --game=all
godot --headless --path . --script res://games/lazer_nfc/tests/lazer_nfc_bindings_test.gd -- --game=all
godot --headless --path . --script res://games/lazer_nfc/tests/lazer_nfc_audio_test.gd -- --game=all
godot --headless --path . --script res://games/lazer_nfc/tests/lazer_nfc_scene_test.gd -- --game=all
godot --headless --path . --script res://games/lazer_nfc/tests/lazer_nfc_intro_test.gd -- --game=all
godot --path . --script res://games/lazer_nfc/tests/lazer_nfc_view_test.gd -- --game=all
godot --path . --script res://games/lazer_nfc/tests/lazer_nfc_layout_test.gd -- --game=all
```

| Test | Covers |
| --- | --- |
| `lazer_nfc_options_test` | Every tunable and binding key is globally unique and clamps; the stats URL is within `ShareQrCode.MAX_URL_BYTES`; ramp choices resolve to real numbers. |
| `lazer_nfc_run_test` | The model: sequence growth, palette growth capped by bound tags, adjacent-repeat rule, scoring, combo, life loss, a wrong answer keeping the original deadline, and equal outcomes at 30 Hz and 60 Hz for the same elapsed time. |
| `lazer_nfc_input_test` | Injected native availability, per-UID debounce, callback age, pause/stop/exit generations, live bindings and neutral motion. |
| `lazer_nfc_bindings_test` | Canonical UIDs, one-to-one mappings, explicit reassignment, merge preservation and failed-read protection. |
| `lazer_nfc_audio_test` | Baked bank and scene-owned audio/haptic scheduling and lifecycle. |
| `lazer_nfc_scene_test` | Real keys/touch, READY practice, assistance, roll call, skip, gestures, NFC loss/fallback, pause and leaving races. |
| `lazer_nfc_intro_test` | The intro loads, is skippable and reaches `Router.goto()`. |
| `lazer_nfc_view_test` | The isolated 3D laboratory: all shades, concealment, framing, bounded effects and reduced motion. |
| `lazer_nfc_layout_test` | Full inherited shell, native deck, portrait/landscape/ultrawide layouts and scrollable results. Requires a graphics display. |

Framework tests to run as well. None of them needs editing: the catalog-driven
ones pick the game up the moment `game.gd` exists, and `custom_keys_test.gd`
proves the custom-key *trait* against a synthetic manifest rather than against
this game, which is exactly why the trait can carry a new game at all.

```bash
godot --headless --path . --script res://tests/game_shell_test.gd -- --game=all
godot --headless --path . --script res://tests/game_options_test.gd -- --game=all
godot --headless --path . --script res://tests/custom_keys_test.gd -- --game=all
godot --headless --path . --script res://tests/single_game_test.gd -- --game=all
godot --headless --path . --script res://tests/game_select_test.gd -- --game=all
godot --headless --path . --script res://tests/instructions_video_test.gd -- --game=all
godot --headless --path . --script res://tests/lives_mode_test.gd -- --game=all
godot --headless --path . --script res://tests/accessibility_test.gd -- --game=all
godot --headless --path . --script res://tests/share_card_test.gd -- --game=all
```

`game_shell_test.gd` drives every catalogued game through a full round,
results, stats, share and replay cycle with `configure_single_player()`, so the
gameplay scene must complete a run headlessly with no NFC, no sensors and no
audio device (§11). `lives_mode_test.gd` and `game_options_test.gd` iterate the
catalog too, which is what checks that clearing `uses_shell_round_rules` hides
the arcade rows instead of breaking them.

Headless rules that shape the code, not just the tests:

- A `--script` run compiles the test and its direct dependencies **before**
  autoloads exist. A test may name an autoload's constants (`Settings.SAVE_PATH`)
  but must resolve the instance from the tree
  (`get_root().get_node_or_null("Settings")`, then `.call(...)`).
- `GameShell` uses autoload instances, so a test must never name it — no
  `is GameShell`, no typed parameter. Load `gameplay.tscn` at runtime and poke
  it with `call`/`get`/`has_method`. That is why the run model, the palette and
  the options are separate, node-free files.
- After adding any `class_name`, run `godot --headless --path . --import` before
  the tests or the global class cache will not know it.

---

## 16. Delivery checklist

Done when a tester with seven sticker tags on a wall and the screen covered can
play from the main menu to the results panel and press **Play Again**.

- [x] Manifest, ten tunables and ten declared keyboard bindings
- [x] Inherited `GameShell` scene and guarded completion/abandonment paths
- [x] Node-free, seeded model with fair deadlines, combos and rolling capped patterns
- [x] Guided tag setup, minimum three hues, skipping and merge-safe relabelling
- [x] Native Android reader, key/touch fallback and bounded optional motion input
- [x] Original 3D toy laboratory, all shade identities, concealment and bounded effects
- [x] READY sound practice, meaningful feedback, achievements, intro, theme and share art
- [x] Original audio/voice authoring sources and a generated 21-label print sheet
- [x] Normal framework boot retained; archived/private folders cannot shadow live manifests
- [x] Assembled scene, audio, responsive layouts and catalog/media integration
- [x] Recorded real-input tutorial and signed ARM64 APK with the native NFC reader
- [ ] Physical-phone NFC and covered-screen playthrough acceptance

Physical NFC timing and covered-screen usability remain device acceptance
work, not something inferred from a desktop fallback. The existing shared
accessibility suite also has a Desk-Can-Saw hint-text assertion that fails
with this game removed; this implementation does not change that game's copy
or weaken the assertion.

**Stretch, explicitly not in v1**

All 21 shade instruments, the printable labels and the real 3D lab are part
of this implementation rather than stretch features.
- Proximity "approach lock" — needs a sensor plugin; do it after NFC
  reliability is measured on five or more devices.
- Camera (ArUco) colour-answer source — only if its different interaction is useful.
- Voice-naming colour-answer source — accessibility path, needs `SpeechRecognizer`.

**Cut, with reasons** (§7.1): tilt aiming (redundant with the tag), flick to
fire (latency, misfires), reach-as-answer (cannot identify a tag), shake actions
(collide with reaching), magnetometer headings (indoor drift, no calibration
UI), camera colour reading (lighting, posture), AR overlay (demands eyes on
screen), ambient-light modes (the game is already eyes-free), pressed-flat
detection (the NFC read is that signal), clap to fire (latency,
self-triggering), ambient-volume difficulty (uncontrollable).

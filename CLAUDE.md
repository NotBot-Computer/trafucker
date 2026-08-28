# Traffic Tower — CLAUDE.md

Godot 4.7 local-multiplayer dodge-traffic party game. See [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md) for the full technical handoff (architecture, decisions, current state, next steps) before making changes — read it first, it's the source of truth for project context.

## Run / validate

Editor (GUI, for playtesting — this project has no automated test suite, manual playtesting is the only way to verify gameplay feel):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot .
```

Headless compile check (catches GDScript parse/compile errors only — does NOT verify gameplay behavior or visuals):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --quit
```
Any `SCRIPT ERROR:` or `Failed to load script` in the output means a script is broken. Clean output (just the engine banner line) means all scripts *reachable from the boot scene* compiled — **the bare command only boots `MainMenu.tscn` and quits, so it never loads `Main.tscn`/`PlayerBoard.gd`/`Road.gd`/`LaneDivider.gd` or anything else only reached by playing through the menu flow.** A parse error in one of those scripts can ship silently past this check (this happened once — see docs/PROJECT_STATE.md §8/§12). When changing a script that isn't in the boot scene's own chain, also run the check against the actual scene, e.g.:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --quit res://scenes/Main.tscn
```

Let the bot play it for you (`scripts/BotDriver.gd`): **1-4** hands player 1-4's board to the AI, or takes it back — on the skin-select screen or at any point mid-round — and **5** cycles EASY/NORMAL/HARD. The player-count screen also has a **1 PLAYER vs BOT** button. Turn every board over to it and the round plays itself, which is the fastest way to watch a change work without holding the keys. Note this is still manual playtesting: it verifies nothing on its own, you have to watch it.

**Pile Up (the tower mode) has no bot**, so there is nothing to hand it to — but it does have a headless harness that plays whole matches and checks the physics and the turn loop:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/TowerProbe.tscn -- --spread=0.3
```
`--spread` is how much of the legal aim range a brick may be steered to: `1.0` models nonsense, `0.1`-`0.3` models a player who is trying. Run both — the interesting signal is the *difference* between them, which is what caught the drop-speed bug in docs/PROJECT_STATE.md §5 session S. Note it sets the commanded position directly rather than pressing keys, so it says nothing about the half-cell step, the dash, the hold-repeat or the soft drop, and nothing at all about how the mode feels.

There is also a much smaller harness for Pile Up's lateral input, which asserts that a dash is *distinguishable* from two ordinary taps rather than that it moves any particular distance (the dash once shipped moving the right distance at the wrong speed, and was invisible — see docs/PROJECT_STATE.md §5 session S):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 60 res://scenes/dev/DashProbe.tscn
```

And one for Pile Up's landings, which asks whether anything is actually under a brick at the moment the player stops being able to steer it:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/LandingProbe.tscn
```

And one for Pile Up's *descent*, which asks whether a brick ever stops falling part way down and stays stopped. It is the only tower probe that steers the way the keyboard does — through `_press_steer()`, on the exact half-cell lattice — and that is the whole point: the others aim with `randf()`, so they never line a brick's faces up flush with the stack the way a player does every single turn (docs/PROJECT_STATE.md §5 session T):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/StallProbe.tscn
```

For measuring bot behaviour rather than looking at it, `--fixed-fps` disables real-time sync and runs the simulation as fast as the machine allows, so a 60-second round takes a few seconds of wall clock:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 120 res://scenes/Main.tscn
```
That boots straight into a round with `GameSettings`' defaults (2 players, no bots), so it's only useful with a throwaway scene that sets `GameSettings.player_count`/`bot_flags`/`bot_difficulty` and instantiates `Main.tscn` itself — see docs/PROJECT_STATE.md §5 session J for what that was used to find.

Godot binary lives at `/opt/homebrew/bin/godot` (CLI) — there's also `Godot.app` in `/Applications` for the GUI editor, but the `godot` CLI command works for both editor (`godot .`) and headless (`godot --headless ...`) use.

## Workflow rules

- **Always let the user playtest a change in the editor before running `git commit`.** This is a standing preference — do not commit immediately after an edit just because headless validation passed clean; headless checks only catch compile errors, not whether the fix actually looks/plays right.
- Only commit once the user confirms (e.g. "it's great", "push it"). Then commit and push to `origin/main` (`github.com/NotBot-Computer/trafucker`) in the same turn unless told otherwise.
- Write commit messages that explain *why*, not just what — this codebase's history is full of physics/illusion bugs where the reasoning matters more than the diff (see docs/PROJECT_STATE.md's "approaches that didn't work" section).

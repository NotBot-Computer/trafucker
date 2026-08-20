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

Godot binary lives at `/opt/homebrew/bin/godot` (CLI) — there's also `Godot.app` in `/Applications` for the GUI editor, but the `godot` CLI command works for both editor (`godot .`) and headless (`godot --headless ...`) use.

## Workflow rules

- **Always let the user playtest a change in the editor before running `git commit`.** This is a standing preference — do not commit immediately after an edit just because headless validation passed clean; headless checks only catch compile errors, not whether the fix actually looks/plays right.
- Only commit once the user confirms (e.g. "it's great", "push it"). Then commit and push to `origin/main` (`github.com/NotBot-Computer/trafucker`) in the same turn unless told otherwise.
- Write commit messages that explain *why*, not just what — this codebase's history is full of physics/illusion bugs where the reasoning matters more than the diff (see docs/PROJECT_STATE.md's "approaches that didn't work" section).

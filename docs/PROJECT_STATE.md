# Traffic Tower — Project State

Last updated: 2026-08-20, at commit `d4b9532` on `main` (working tree clean, pushed to `origin/main` — `github.com/NotBot-Computer/trafucker`).

This document is a standalone handoff. A new session should be able to continue this project using only the repository, `CLAUDE.md`, and this file — no prior conversation is available.

## 1. What this project is

**Traffic Tower** is a local split-screen party game built in **Godot 4.7** (GL Compatibility renderer). Each player gets their own vertically-scrolling lane board side by side on one screen; you steer left/right to dodge oncoming traffic, and the road speeds up over time. Whoever survives longest (covers the most distance) wins the round. Structurally it's meant to grow into a "many small competitive modes" party game (inspired by *Tricky Towers*) — currently only one mode, **Don't Crash**, exists.

Full player-facing description, controls, and art notes are in [README.md](../README.md) — that file is accurate and up to date; don't duplicate it here, read it for the "how to play" side.

## 2. Architecture / structure

Scene tree flow: `MainMenu.tscn` → `PlayerSelect.tscn` (pick 2–4 players) → `SkinSelect.tscn` (each player cycles/locks a car color) → `Main.tscn` (the actual round).

`Main.tscn` instantiates one `PlayerBoard.tscn` per player side by side inside `BoardsContainer`, and one `LaneDivider.tscn` between each adjacent pair inside `DividersContainer`. Each `PlayerBoard` owns its own `Road` (background), `PlayerCar`, and `ObstacleContainer` (spawned traffic). `LaneDivider` is a separate, independently-timed decorative strip — it is **not** a child of `PlayerBoard` and does not share state with it directly (see §7, this is a deliberate but fragile design).

Global/shared state lives in the `GameSettings` autoload (`scripts/GameSettings.gd`, registered in `project.godot` under `[autoload]`): player count, chosen skins, the `PLAYER_SKINS` and `TRAFFIC_KINDS` tables (textures + spawn weights + per-kind speed ranges), and the 4-way keyboard binding table (`PLAYER_CONFIGS`).

## 3. Key files

| File | Responsibility |
|---|---|
| `scripts/GameSettings.gd` | Autoload. Player count, skins, `TRAFFIC_KINDS` (vehicle art + size + spawn weight + speed range), `PLAYER_CONFIGS` (per-player key bindings). |
| `scripts/Main.gd` | Builds N `PlayerBoard`s + dividers for the chosen player count, owns round state (`playing`/`gameover`), restart-on-Enter, Esc-to-menu. |
| `scripts/PlayerBoard.gd` | The core gameplay loop for one player: steering physics (momentum-based, not lane-snapped), dash, drift, obstacle spawning, per-obstacle speed, collision → crash. |
| `scripts/Road.gd` | Lane-position math (`lane_center_x`, `lane_width`) and draws the scrolling road texture. |
| `scripts/LaneDivider.gd` | Draws the scrolling grass/tree median between boards. Runs its own independent speed-ramp timer (mirrors `PlayerBoard`'s constants but is a separate copy — see §7 and §9). |
| `scripts/Car.gd` | Generic vehicle node (used for both the player car and every traffic obstacle). Shows a placeholder `Polygon2D` shape until a texture is assigned via `set_texture()`, then scales that texture to the requested size. |
| `scripts/MainMenu.gd`, `PlayerSelect.gd`, `SkinSelect.gd` | Menu flow screens. Nothing subtle here. |
| `scenes/*.tscn` | Godot scene files pairing the above scripts with their node trees. |
| `sprites/cars/*.png`, `sprites/road/*.png` | Real hand-cropped art (not procedural). See README's "Car art" / "Road art" sections for provenance. |

## 4. What's already implemented

- Full menu flow: main menu → 2/3/4 player select → per-player skin select (duplicate-skin avoidance, ready-up gating) → round start.
- Momentum-based steering (not lane-snapping) with configurable top speed and grip response.
- **Dash**: double-tap a direction within a short window → fast eased snap exactly one lane over, with a fading afterimage trail, on a per-player cooldown.
- **Drift**: triggered by a genuine velocity reversal (pressing the opposite direction while still carrying real speed the other way) — not a separate button/gesture. Nose points where you steer, actual momentum lags behind at reduced grip, leaves a twin skid-mark trail. Persists while steering either direction, ends the instant both keys release.
- Traffic: 7 vehicle kinds (sedan, SUV, pickup, van, truck, bus, motorcycle) with weighted random spawn selection, real cropped sprite art, per-kind size ratios matched to each sprite's real aspect ratio.
- Speed ramp: `current_speed() = BASE_SPEED + elapsed * SPEED_PER_SECOND` (160 base, +6/s), same formula shared conceptually across `PlayerBoard` and `LaneDivider`.
- Round scoring by distance traveled; game-over overlay declares the winner; Enter restarts, Esc returns to menu.
- Road and median rendered as tiled real-texture scrolling strips (not procedurally drawn shapes) — both cropped from the same source art so grass/guardrail styling matches exactly (`Road.SHOULDER_RATIO` is tuned to the texture's actual asphalt width).

## 5. What we worked on this session

The whole session was one bug chain, reported by the user as: *"trees and road moves at a different speed and cars look like it is going backward."* Three distinct, real bugs were found and fixed in sequence — **all three fixes are necessary; none of them individually resolved the full symptom**:

1. **`LaneDivider` never reset across rounds** (commit `b049efe`). `LaneDivider._process` accumulates its own `elapsed`/`distance` from the moment the node is created and never stops. `Main._start_round()` resets every `PlayerBoard`'s `elapsed`/`distance` to 0 on both the first round and every restart, but never touched the dividers. After any restart-after-crash, the road/traffic speed would snap back to `BASE_SPEED` while the tree median kept accelerating from wherever it had already climbed to — a growing speed mismatch between trees and road. Fix: added `LaneDivider.reset()`, called from `Main._start_round()` for every child of `dividers_container` alongside each board's `start_round()`.

2. **Road/median tiles scrolled in the opposite direction from traffic** (commit `5353b8a`). This was the primary cause of "cars look like they're going backward." `Road._draw()` and `LaneDivider._draw()` both anchored their tile loop at `y = -scroll`, and as `distance` (and therefore `scroll`) grew, that shifts the rendered pattern toward **negative y** (up, off the top of the screen). But obstacle traffic in `PlayerBoard._process` moves via `child.position.y += speed * speed_mult * delta` — **positive y** (down, toward the player), which is the geometrically correct direction for "you are driving forward." Background scrolling up while foreground traffic scrolls down is a direct visual contradiction — the road reads as sliding the wrong way under the cars. Fix: changed the anchor to `y = scroll - tile_h` in both `_draw()` methods, which makes the tiled pattern slide toward +y (down) as `distance` grows, matching the traffic direction. Coverage math (tile spacing, no gaps) is unaffected — only the anchor point's sign flipped.

3. **Some individual obstacles still looked like they were reversing, even after fix #2** (commit `d4b9532`). Root cause: `PlayerBoard._spawn_obstacle()` picked `speed_mult` uniformly from `randf_range(0.78, 1.28)` and used it as `child.position.y += speed * speed_mult * delta` directly. The road texture itself always scrolls at exactly `speed` (i.e., implicitly `speed_mult == 1.0`). Any obstacle with `speed_mult > 1.0` therefore closes toward the player **faster than the road surface's own scroll rate** — which is only physically possible if that car is driving in reverse relative to the road. Visually this reads as the car sliding backward across the lane stripes, even though its on-screen y is still increasing. Fix: reworked the whole speed model in terms of relative motion — an obstacle's screen speed represents `(road speed − the vehicle's own forward speed)`, which for any car that is actually driving forward is always strictly less than the road's own scroll rate. Implemented as per-`TRAFFIC_KINDS`-entry `speed_frac_min`/`speed_frac_max` fields (all kept below 1.0, capped at 0.95 max — see the invariant in §7), replacing the single flat 0.78–1.28 range. Trucks/buses get high fractions (0.75–0.95 → slow real-world speed → you close in on them fast); motorcycles get low fractions (0.35–0.65 → fast real-world speed → they roughly keep pace with you, hard to catch); sedans/SUVs/pickups/vans sit in between (0.55–0.9).

User confirmed the result looks correct after fix #3 ("its great").

## 6. Key technical decisions & why

- **Relative-speed model for traffic, not absolute multipliers.** An obstacle's screen-space closing speed must always be expressed as *(reference scroll rate − vehicle's own forward speed)*, never as an independent multiplier applied to the base speed. This is the single most important invariant introduced this session — see §7.
- **Per-vehicle-kind speed ranges instead of one global range.** Chosen over a single flat range because (a) it fixes the >1.0 bug structurally — every kind's range is authored below 1.0 — and (b) it adds gameplay texture "for free" (heavy vehicles feel slow/easy to catch, motorcycles feel nimble) without extra systems.
- **Dividers keep their own independent timer rather than reading a board's speed directly.** This predates this session's changes and was not restructured, only patched (see §7 for why this is a known fragility, not an endorsement).
- **Real cropped-texture tiling for road/median instead of procedural drawing.** Predates this session (commit `374f392`); kept as-is. Rationale (from the commit): both textures come from the same source art so grass/guardrail styling matches exactly, and it looks better than procedural shapes.

## 7. Assumptions, constraints, conventions that must be preserved

- **Godot 2D coordinate convention: +y is down.** Any code that scrolls the road, median, or traffic must treat *increasing y* as "moving toward the player" (who sits near the bottom of each board). This is easy to get backward (as fix #2 shows) — always sanity-check the sign against `PlayerBoard._process`'s obstacle movement line (currently `child.position.y += speed * speed_mult * delta`), which is the canonical "forward" direction.
- **Invariant: every `TRAFFIC_KINDS` entry's `speed_frac_max` must stay below `1.0`.** This encodes "no traffic vehicle may close in on the player faster than the road itself scrolls." Violating it (as the pre-session code did with 1.28) reintroduces the "driving backward" visual bug. If you add a new vehicle kind, give it `speed_frac_min`/`speed_frac_max` in roughly the `[0.3, 0.95]` band and keep the max end away from `1.0` (a small safety margin, not just `< 1.0` exactly, keeps the effect visually convincing even at high round speeds).
- **`Road._draw()` and `LaneDivider._draw()` must use the same tile-anchoring convention.** They currently both use `y = scroll - tile_h`. If one is changed without the other, the road and median will visibly scroll at different apparent rates/directions again (this is exactly bug #2 in miniature). Treat these two functions as a matched pair.
- **`Main._start_round()` must reset every board AND every divider.** If a new decorative or moving element is added to `Main.tscn` with its own internal timer, it must also be reset here, or it will desync after the first restart the same way `LaneDivider` did (bug #1).
- **`BASE_SPEED` / `SPEED_PER_SECOND` are currently duplicated** as separate constants in `PlayerBoard.gd` (160 / 6) and `LaneDivider.gd` (160 / 6, same values, copy-pasted). They must be kept numerically identical or the road and median will scroll at different rates. See §9 for the recommended fix (centralize this).
- **No automated test suite exists.** `godot --headless --quit` only catches GDScript compile/parse errors — it does not verify gameplay behavior, timing, or visual correctness. All three bugs this session were diagnosed by reading the physics/draw math, not by running a test. **The user's explicit workflow preference: always let them playtest a change in the editor before committing** — do not commit right after an edit just because headless validation passed. Wait for explicit confirmation (e.g. "it's great", "push it") before running `git commit`.
- Commits in this repo tend to explain *why*, with the physical/visual reasoning spelled out (see the last three commit messages). Keep that convention — this codebase has a history of subtle sign/reference-frame bugs where the reasoning is what prevents regressions.

## 8. Approaches that were tried and did NOT work (don't repeat these)

- **Assuming the restart-desync fix (bug #1 / `LaneDivider.reset()`) would resolve the "cars going backward" complaint.** It didn't — the user reported it was still happening after that fix shipped. That fix was still correct and necessary (it's a real, separate bug), but it was not the primary cause of the reported symptom. Lesson: when a background-vs-foreground motion complaint persists after a timing/sync fix, check the *direction* of motion next, not just the *rate*.
- **Assuming the direction fix (bug #2) alone would resolve it.** After shipping the `y = -scroll` → `y = scroll - tile_h` change, the user reported *some* cars still looked backward — not all of them. This pointed away from a global/systemic direction bug (already fixed) and toward a per-obstacle issue, which was bug #3 (the `speed_mult` range exceeding 1.0). Lesson: "some cars" vs. "everything" is a meaningful diagnostic signal — a global draw-direction bug affects everything uniformly; a per-obstacle backward artifact points at per-obstacle speed logic.
- **The original `speed_mult` range of `0.78–1.28`** (introduced in commit `374f392`, before this session) was an attempt to add speed variety ("cars drift ahead of or fall behind each other") but was implemented as a naive multiplier on the base speed without grounding it in the relative-speed model. Do not reintroduce a flat range that crosses `1.0` — see the invariant in §7.

## 9. Known bugs, limitations, unresolved problems

- **`BASE_SPEED`/`SPEED_PER_SECOND` duplication** (see §7) is a latent fragility: nothing enforces the two copies (in `PlayerBoard.gd` and `LaneDivider.gd`) stay equal. Currently they do, and the game looks correct, but this should be refactored (see §11) before anyone touches speed tuning again.
- **`LaneDivider` doesn't read a real board's speed** — it maintains its own parallel timer that happens to use the same constants and gets reset at the same point in `Main._start_round()`'s loop, so in practice it stays in lockstep with the boards. But this is coincidental synchronization via duplicated logic, not a structural guarantee. In a multi-divider (3–4 player) game, all dividers and all boards are reset in the same `_start_round()` call within the same frame, so they should stay aligned — this has not been stress-tested beyond normal play.
- **Only one game mode exists** ("Don't Crash"). The README's roadmap (more modes, gamepad support, web/desktop export) is entirely unstarted — no code toward any of it exists yet.
- **No CI, no automated tests, no export presets configured.** Validation is headless-compile-check plus manual playtesting only.
- Multi-round replay under 3–4 players and extended play sessions (many minutes, high speed ramp) have not been specifically stress-tested this session beyond the user's own playtest confirmation — worth another pass if traffic issues resurface at very high speeds.

## 10. Exact current state

- Branch: `main`. HEAD: `d4b9532` ("Rework traffic speed model to fix remaining backward-car illusion"). Working tree clean. Pushed to `origin/main` (`github.com/NotBot-Computer/trafucker`).
- All three bugs described in §5 are fixed, committed, and pushed. The user confirmed the fix looks correct in-editor.
- `docs/PROJECT_STATE.md` (this file) and `CLAUDE.md` are new, uncommitted as of this writing — commit them once the user reviews/confirms (per the standing playtest-before-commit rule, though these are docs, not gameplay code, so use judgment — the user may want docs committed without a "playtest").

## 11. Recommended next steps, in order

1. **Confirm this handoff doc + `CLAUDE.md` with the user, then commit them.**
2. **Stress-test the traffic fix further**: play multiple full rounds back-to-back (crash → restart, repeatedly), try 3- and 4-player modes, and let a round run long enough for `current_speed()` to get large, watching for any remaining directional or speed artifacts.
3. **Refactor the duplicated speed constants** (`BASE_SPEED`, `SPEED_PER_SECOND` in both `PlayerBoard.gd` and `LaneDivider.gd`) into a single source of truth — e.g. move them to `GameSettings` or a small shared `SpeedRamp` helper/autoload, and have both scripts read from it. This removes the "keep two copies in sync by hand" fragility noted in §7/§9 before anyone touches speed tuning again.
4. **Consider whether `LaneDivider` should derive its scroll distance from an adjacent `PlayerBoard`/`Road` directly** instead of maintaining its own parallel timer, which would eliminate the desync class of bug structurally rather than by careful duplication. Only worth doing if #3 doesn't feel sufficient.
5. **Move on to README roadmap items** once the above is solid: additional game modes, gamepad support, web/desktop export presets — in whatever order the user prioritizes.

## 12. Non-obvious implementation details

- **Godot 2D: +y is down, +x is right.** Repeatedly relevant this session — see §7.
- **`GameSettings` is an autoload singleton**, not a resource you instantiate — it's globally accessible as `GameSettings.foo` from any script without a reference, and its `const` tables (`PLAYER_SKINS`, `TRAFFIC_KINDS`, `PLAYER_CONFIGS`) `preload()` every texture at parse time, so adding vehicle kinds means editing this one file's array literals, not spawning new resources.
- **`Car.gd`'s placeholder `Polygon2D` shapes auto-hide** the moment `set_texture()` is called (`body.visible = false; windshield.visible = false` in `_rebuild()`) — you never need to manually hide them when assigning real art to a new `Car` instance.
- **`speed_mult` (the per-obstacle meta key) is a closing-speed *fraction* of the current road speed, not a real-world speed.** Read `PlayerBoard._process`'s obstacle-movement block (`child.position.y += speed * speed_mult * delta`) together with `GameSettings.TRAFFIC_KINDS`' `speed_frac_min`/`speed_frac_max` comment block to understand it — the comment there explains the physical reasoning in full and should be kept in sync with any future changes to this system.
- **Tile-anchoring formula `y = scroll - tile_h`** (in both `Road._draw()` and `LaneDivider._draw()`): `scroll` is `fmod(distance, tile_h)`, always in `[0, tile_h)`. This anchors the first (partially off-screen) tile at `y ∈ [-tile_h, 0)` and lets it (and all tiles after it) drift toward `y = 0` and beyond as `distance` grows, which is what makes the whole pattern appear to slide downward. If you ever need to reverse the visual scroll direction intentionally (e.g. a "reverse" game mode), flip this to `y = -scroll` deliberately — but remember that then also requires making obstacle motion negative to match (see the §7 invariant about keeping `Road`/`LaneDivider`/traffic direction consistent).
- **Dash and drift are purely lateral (x-axis) mechanics** — they do not interact with the forward-scroll speed system described above at all. `car_vx`/`car_x` in `PlayerBoard.gd` are entirely separate from `distance`/`current_speed()`. Don't conflate the two systems when debugging either one.

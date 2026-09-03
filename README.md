# Traffic Tower

A local party game about cars, played two ways: race them, or stack them. Styled after retro top-down pixel art, with a "many small competitive modes" structure inspired by *Tricky Towers*.

Built in **Godot 4**.

## Modes

**Don't Crash** — split-screen. Steer between lanes, avoid traffic, survive as long as possible. Speed ramps up over time. Three lives each: a crash costs one and knocks you down to a crawl, and you're only out once all three are gone. Whoever covers the most distance wins the round.

**Pile Up** — one shared tower. Players take turns steering car-shaped bricks down onto a single narrow platform, under real physics. When everything stops moving, anything that fell off costs the player who dropped it a life. Three lives each; last builder standing wins.

## Playing it

Launch the game and you'll get: pick a mode → pick 2, 3, or 4 players → each player cycles and locks in a color → off you go.

In **Don't Crash** that colour is your car, the three hearts trailing behind it, and each board always has 5 lanes, regardless of player count. In **Pile Up** it marks whichever brick is currently in the air — every brick already on the pile looks the same, whoever put it there — and the three hearts on your HUD card, the same pip in the same colour as the ones behind a car in the other mode.

### Playing alone, or against the computer

*(Don't Crash only — there is no Pile Up AI yet.)*

Pick **1 PLAYER vs BOT** on the player-count screen and you'll race a computer-driven opponent.

More generally, **the 1-4 keys hand player 1-4's board to the AI, or take it back** — on the car-color screen or at any moment during a race. **5** cycles the AI between EASY, NORMAL and HARD. A board the AI is driving is labelled `BOT` under its boost bar. Hand over every board and the game plays itself, which is a handy way to watch a mode without playing it.

The AI drives the same car with the same physics you do — it steers, dashes, drifts, spends boost and picks up skills through exactly the same controls, it just doesn't need a keyboard. Difficulty is how far ahead it plans and how quickly it reacts, not what it's allowed to see.

## Controls

| Player | Left | Right | Down | Confirm / Dash | Rotate ccw / cw |
| ------ | ---- | ----- | ---- | -------------- | --------------- |
| P1     | A    | D     | S    | W              | Q / E           |
| P2     | ←    | →     | ↓    | ↑              | , / .           |
| P3     | F    | H     | G    | T              | R / Y           |
| P4     | J    | L     | K    | I              | U / O           |

### Pile Up

Your brick starts falling the moment it appears — there is no drop button, just a few seconds to place it.

- **Left / right** move it **exactly half a block**. Hold to repeat.
- **Confirm** dashes **exactly one whole block** in the direction you're holding (or the last one you pressed) — same distance as two taps, but covered in one fast sweep with a trail behind it, so you can see it land.
- **Rotate keys** turn it a quarter turn at a time.
- **Down** makes it fall faster, once you like the line.

You can walk a brick up to two blocks past the platform edge if you want to — that is the whole risk/reward of the mode, and yes, you can walk one clean off the side and lose it.

Coming up against the side of a taller part of the tower doesn't end your turn. You keep steering for as long as you like and can always back out of it — a turn ends when something is actually *underneath* the brick, and at no other time.

The moment the brick touches down it stops being yours and becomes ordinary physics: it tips, slides and settles, and so does everything under it. The turn does not end when it lands, it ends when the *whole tower* has stopped moving — so a brick that settles innocently and then shoves the pile over five seconds later still counts against you.

### Don't Crash

Double-tap left or right (quickly, twice back-to-back) to **dash** exactly one lane over — a fast eased snap with a fading afterimage trail, on a short per-player cooldown.

While already carrying real speed one way, press the opposite direction to start **drifting** — no separate gesture needed, just a genuine sudden reversal. The car's nose points wherever you're steering, but its actual momentum lags behind at reduced grip (not increased speed), so it visibly slides, leaving a twin skid-mark trail from the rear wheels. Keeps drifting as long as you keep steering in either direction; lets go of grip the instant you release both keys.

You have **three lives**, shown as three hearts in your own car's colour trailing along the road behind you. Hitting traffic wrecks the car you hit, costs a heart, and drops you to a crawl — you then blink for a couple of seconds, during which traffic passes straight through you while you get your speed back. Lose all three and you're out, and the round ends once nobody is left driving.

Every so often a glowing pickup appears in a lane. Drive over it and two icons come up either side of your car — the round never pauses for this. The **left** one (your "opponent" key) sends something nasty to every *other* player; the **right** one (your "self" key) helps you. Which skill each side is offering is rolled when the icons appear and shown on them, so what you see is what you get. There are nine:

| | Skill | What it does |
|---|---|---|
| self | **Tank Mode** | 6s as an invincible tank that crushes traffic; your boost key fires the cannon |
| self | **Nitro** | lifts off and rockets up the road at 2.85x, flying *over* the traffic |
| self | **Make Way** | 5s of siren — your car becomes a police cruiser and traffic ahead signals and pulls out of your lane |
| self | **Pit Stop** | instantly gives back a lost life; if you have all three, fills your boost bar instead |
| self | **Compact** | your car shrinks to two-thirds width for 7s, so tight gaps become gaps |
| opponent | **Taxi** | a reckless cab barges onto everyone else's board and runs riot for 11s |
| opponent | **Detour** | lines of roadworks barriers scroll down everyone else's road with one gap to find |
| opponent | **Oil Slick** | everyone else loses their grip for 5s — the car overshoots, fishtails and arrives late |
| opponent | **Smoke Screen** | a bank of smoke hides the top of everyone else's road for 5s, so traffic emerges late |

The six newer ones each live in their own file under `scripts/skills/`; their icons and Detour's barrier are placeholders drawn in code — `docs/SKILL_ART_BRIEF.md` is the brief for real art, which drops in by filename with no code change.

Press **Enter** to restart after a round ends. Press **Esc** during a round to return to the main menu. **1-4** toggle the AI for each player and **5** changes its difficulty (see above).

## Running it

Open the project folder in the Godot 4 editor (`godot --path .` from this directory, or `Import` from the project manager), then press **F5** / the Play button.

## Backdrop and ground

Pile Up plays in front of `sprites/bg/tower_backdrop.png`, in two layers cut from that one image.

The **backdrop** is drawn in screen space on its own layer and scrolled at a fraction of the camera. Screen-space rather than part of the world on purpose: the camera pans up without limit as the tower grows, so world-space art would be left behind within a few bricks. Above the picture's own top edge the sky simply continues in the image's own sky colour, so a tall tower climbs into open sky instead of into a hard edge.

The **near ground** is the grass shelf from the bottom of the same image, drawn in world space at the foot of the tower and *in front of* the bricks — so a brick knocked off the tower slides down behind the grass and is gone. It tracks the camera exactly, because it is where the tower actually stands. The two layers are aligned at the start of a match and separate as the tower climbs, near ground falling away faster than far.

The tower itself stands on a rock outcrop whose body is cut from the same picture's earth band, so it is literally made of the stone the rest of the world is made of rather than painted to look like it.

## Brick art

Pile Up's seven bricks (`sprites/blocks/piece_*.png`) are the standard tetromino shapes drawn as clusters of top-down cars, cropped from one supplied sheet by `scripts/dev/extract_blocks.py`. That script removes the sheet's background *and its drop shadows* by flood-filling in from the border — neither can be separated from the cars' own black outlines by brightness alone, but only one of them is reachable from outside the art. It also normalises every piece to an exact grid of square cells, since the source sheet draws its cells anywhere from 4% to 14% taller than they are wide; `GameSettings.TETROMINOES` can then give each piece its collision as plain cell-unit rectangles.

## Car art

Cars are real sprites (`sprites/cars/*.png`) — top-down orthographic pixel art across 10 vehicle kinds: sedans (12 colors: 6 selectable player skins + 6 traffic-only), SUVs, pickups, vans, sports cars, semi trucks, pickups towing trailers, transit buses, coaches, and motorcycles. All of it was cropped and cleaned up from hand-drawn vehicle reference sheets, except the motorcycles, which stayed on the original top-down art — the newer motorcycle sheet is drawn as a front elevation, which reads as riding toward you in a top-down game. `GameSettings.TRAFFIC_KINDS` holds each kind's textures, size ratios, and spawn weight — the weights total 100, so each reads directly as a percentage of traffic: sedans 30%, SUVs 16%, pickups 12%, vans 11%, sports cars 9%, semi trucks 7%, trailers 5%, transit buses 3%, coaches 2%, motorcycles 5%. `PlayerBoard.gd` picks a weighted-random kind and texture for every spawned traffic `Car`.

The two long kinds are the ones that change how a lane plays: a **semi truck** is 179px of road at a 5-lane board's scale — 29% of the board's whole height and a **towed trailer** 124px, against a sedan's 56px, and both drive slowly enough that you close on them fast. **Sports cars** sit at the other end — they nearly keep pace with you, so they hang alongside instead of rushing past.

Every `Car` (`scenes/Car.tscn`) has an empty `Sprite2D` child, so you can swap in your own art any time: open it in the editor and drag a PNG onto the Sprite2D's **Texture** property in the Inspector, or call `set_texture()` from code (see `PlayerBoard.gd` for examples). The placeholder shape (a colored `Polygon2D`) automatically hides once a texture is assigned. `Car.gd` scales whatever texture is provided to the car's collision size.

## Road art

The road and median are real textures too (`sprites/road/*.png`), both cropped from the same hand-drawn source image so their grass/guardrail style matches exactly. `Road.gd` and `LaneDivider.gd` scroll them by drawing repeated tiles offset by accumulated distance, instead of procedurally drawing lanes/grass. `Road.SHOULDER_RATIO` is tuned to the texture's actual asphalt width so cars only ever drive on the gray part.

Traffic also moves at slightly different speeds per vehicle (`PlayerBoard._spawn_obstacle` assigns each one a random `speed_mult`) so gaps open and close between cars instead of the whole field scrolling in perfect lockstep.

## Project structure

```
project.godot
sprites/
  cars/               top-down vehicle PNGs (sedans, SUVs, pickups, vans, sports cars, semi trucks, trailers, buses, coaches, motorcycles)
  road/               road + median tile textures, cropped from one source image
  blocks/             the seven car-tetromino bricks used by Pile Up
  bg/                 Pile Up's parallax backdrop
  ui/                 countdown glyphs, and the heart both modes show a life with
  skills/             PLACEHOLDER choice-icon glyphs + Detour's barrier, generated by scripts/dev/make_placeholder_skill_icons.py
scenes/
  MainMenu.tscn       title screen, mode picker
  PlayerSelect.tscn    choose 2/3/4 players
  SkinSelect.tscn      each player picks + locks in a car sprite
  Main.tscn            N PlayerBoards side by side, round state, restart UI
  PlayerBoard.tscn     one player's road + car + obstacle spawner
  Car.tscn             sprite/placeholder + collision, reused for player and traffic
  LaneDivider.tscn     grass + trees median between adjacent player boards
  TowerMode.tscn       Pile Up: the shared tower, its platform and its HUD
  TowerPiece.tscn      one car-tetromino brick (a real RigidBody2D)
scripts/
  GameSettings.gd      autoload: player count, chosen skins, sprite tables, key bindings
  MainMenu.gd
  PlayerSelect.gd
  SkinSelect.gd        dynamic per-player sprite-pick panels, duplicate-skin avoidance
  Main.gd              instantiates PlayerBoards + dividers for the chosen player count
  PlayerBoard.gd        steering physics, spawning, scoring, collision handling
  BotDriver.gd          the AI: reads the traffic, plans a lane, drives PlayerBoard's own controls
  Road.gd               lane math and scrolling road-texture rendering
  Car.gd                 swaps between placeholder shape and an assigned texture
  HeartPips.gd          the life pip both modes draw, and its per-player recolour
  LaneDivider.gd         scrolling grass/tree median renderer
  TowerMode.gd          Pile Up: turn order, drop/settle/resolve loop, lives, camera
  TowerPiece.gd         one brick: collision from cell rects, physics material, fall cap
  TowerMode.gd          (see above) also owns the shape-query movement model
  TowerHUD.gd           Pile Up's side-column panels — lives, next brick, controls
  TowerBackground.gd    Pile Up's parallax backdrop
  TowerGround.gd        Pile Up's near ground — a foreground layer bricks fall behind
  skills/               Don't Crash's modular skills — one file each, plus the base class, the catalog and the overlay node
  dev/                  headless measurement harnesses, not part of the game
```

## Roadmap

- More competitive mini-modes beyond the two above (time attack, reverse traffic, narrowing lanes, item pickups, etc.)
- An AI that can play Pile Up, so it has the same hand-it-to-a-bot testing loop Don't Crash has
- Gamepad support
- Export to web (HTML5) and/or desktop builds

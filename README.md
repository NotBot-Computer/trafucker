# Traffic Tower

A local split-screen party game: dodge oncoming traffic, don't crash, and outlast your friends. Styled after retro top-down pixel racers, with a "many small competitive modes" structure inspired by *Tricky Towers*.

Built in **Godot 4**.

## Current mode

**Don't Crash** — steer between lanes, avoid traffic, survive as long as possible. Speed ramps up over time. Whoever covers the most distance before crashing wins the round.

## Playing it

Launch the game and you'll get: **Play** → pick 2, 3, or 4 players → each player cycles and locks in a car color → race starts. Each board always has 5 lanes, regardless of player count.

### Playing alone, or against the computer

Pick **1 PLAYER vs BOT** on the player-count screen and you'll race a computer-driven opponent.

More generally, **the 1-4 keys hand player 1-4's board to the AI, or take it back** — on the car-color screen or at any moment during a race. **5** cycles the AI between EASY, NORMAL and HARD. A board the AI is driving is labelled `BOT` under its boost bar. Hand over every board and the game plays itself, which is a handy way to watch a mode without playing it.

The AI drives the same car with the same physics you do — it steers, dashes, drifts, spends boost and picks up skills through exactly the same controls, it just doesn't need a keyboard. Difficulty is how far ahead it plans and how quickly it reacts, not what it's allowed to see.

## Controls

| Player | Left | Right | Confirm (skin select) |
| ------ | ---- | ----- | ---------------------- |
| P1     | A    | D     | W                       |
| P2     | ←    | →     | ↑                       |
| P3     | F    | H     | T                       |
| P4     | J    | L     | I                       |

Double-tap left or right (quickly, twice back-to-back) to **dash** exactly one lane over — a fast eased snap with a fading afterimage trail, on a short per-player cooldown.

While already carrying real speed one way, press the opposite direction to start **drifting** — no separate gesture needed, just a genuine sudden reversal. The car's nose points wherever you're steering, but its actual momentum lags behind at reduced grip (not increased speed), so it visibly slides, leaving a twin skid-mark trail from the rear wheels. Keeps drifting as long as you keep steering in either direction; lets go of grip the instant you release both keys.

Press **Enter** to restart after a round ends. Press **Esc** during a round to return to the main menu. **1-4** toggle the AI for each player and **5** changes its difficulty (see above).

## Running it

Open the project folder in the Godot 4 editor (`godot --path .` from this directory, or `Import` from the project manager), then press **F5** / the Play button.

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
scenes/
  MainMenu.tscn       title screen, Play button
  PlayerSelect.tscn    choose 2/3/4 players
  SkinSelect.tscn      each player picks + locks in a car sprite
  Main.tscn            N PlayerBoards side by side, round state, restart UI
  PlayerBoard.tscn     one player's road + car + obstacle spawner
  Car.tscn             sprite/placeholder + collision, reused for player and traffic
  LaneDivider.tscn     grass + trees median between adjacent player boards
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
  LaneDivider.gd         scrolling grass/tree median renderer
```

## Roadmap

- More competitive mini-modes beyond "don't crash" (time attack, reverse traffic, narrowing lanes, item pickups, etc.)
- Gamepad support
- Export to web (HTML5) and/or desktop builds

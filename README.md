# Traffic Tower

A local split-screen party game: dodge oncoming traffic, don't crash, and outlast your friends. Styled after retro top-down pixel racers, with a "many small competitive modes" structure inspired by *Tricky Towers*.

Built in **Godot 4**.

## Current mode

**Don't Crash** — steer between lanes, avoid traffic, survive as long as possible. Speed ramps up over time. Whoever covers the most distance before crashing wins the round.

## Playing it

Launch the game and you'll get: **Play** → pick 2, 3, or 4 players → each player cycles and locks in a car color → race starts. Each board always has 5 lanes, regardless of player count.

## Controls

| Player | Left | Right | Confirm (skin select) |
| ------ | ---- | ----- | ---------------------- |
| P1     | A    | D     | W                       |
| P2     | ←    | →     | ↑                       |
| P3     | F    | H     | T                       |
| P4     | J    | L     | I                       |

Double-tap left or right (quickly, twice back-to-back) to **dash** exactly one lane over — a fast eased snap with a fading afterimage trail, on a short per-player cooldown.

Press **Enter** to restart after a round ends. Press **Esc** during a round to return to the main menu.

## Running it

Open the project folder in the Godot 4 editor (`godot --path .` from this directory, or `Import` from the project manager), then press **F5** / the Play button.

## Car art

Cars are real sprites (`sprites/cars/*.png`) — top-down orthographic pixel art across 7 vehicle kinds: sedans (12 colors: 6 selectable player skins + 6 traffic-only), SUVs, pickups, vans, trucks, buses, and motorcycles. Most were cropped and cleaned up from a hand-drawn top-down vehicle reference sheet; motorcycles are code-generated since the reference's motorcycles were drawn front-on rather than top-down. `GameSettings.TRAFFIC_KINDS` holds each kind's textures, size ratios, and spawn weight (sedans most common, buses/motorcycles rarest); `PlayerBoard.gd` picks a weighted-random kind and texture for every spawned traffic `Car`.

Every `Car` (`scenes/Car.tscn`) has an empty `Sprite2D` child, so you can swap in your own art any time: open it in the editor and drag a PNG onto the Sprite2D's **Texture** property in the Inspector, or call `set_texture()` from code (see `PlayerBoard.gd` for examples). The placeholder shape (a colored `Polygon2D`) automatically hides once a texture is assigned. `Car.gd` scales whatever texture is provided to the car's collision size.

## Project structure

```
project.godot
sprites/
  cars/               generated top-down vehicle PNGs (sedans, SUVs, pickups, vans, trucks, buses, motorcycles)
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
  Road.gd               lane math and road/dash rendering
  Car.gd                 swaps between placeholder shape and an assigned texture
  LaneDivider.gd         scrolling grass/tree median renderer
```

## Roadmap

- More competitive mini-modes beyond "don't crash" (time attack, reverse traffic, narrowing lanes, item pickups, etc.)
- Gamepad support
- Export to web (HTML5) and/or desktop builds

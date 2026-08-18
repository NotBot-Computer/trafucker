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

Press **Enter** to restart after a round ends. Press **Esc** during a round to return to the main menu.

## Running it

Open the project folder in the Godot 4 editor (`godot --path .` from this directory, or `Import` from the project manager), then press **F5** / the Play button.

## Adding your own art

Every car (`scenes/Car.tscn`) has an empty `Sprite2D` child. Open it in the editor and drag a PNG onto the Sprite2D's **Texture** property in the Inspector — no code changes needed. The placeholder shape (a colored `Polygon2D`) automatically hides once a texture is assigned. `Car.gd` scales whatever texture you provide to the car's collision size.

## Project structure

```
project.godot
scenes/
  MainMenu.tscn       title screen, Play button
  PlayerSelect.tscn    choose 2/3/4 players
  SkinSelect.tscn      each player picks + locks in a car color
  Main.tscn            N PlayerBoards side by side, round state, restart UI
  PlayerBoard.tscn     one player's road + car + obstacle spawner
  Car.tscn             sprite/placeholder + collision, reused for player and traffic
scripts/
  GameSettings.gd      autoload: player count, chosen skins, per-player key bindings
  MainMenu.gd
  PlayerSelect.gd
  SkinSelect.gd        dynamic per-player color-pick panels, duplicate-color avoidance
  Main.gd              instantiates PlayerBoards for the chosen player count, centers them
  PlayerBoard.gd        steering physics, spawning, scoring, collision handling
  Road.gd               lane math and road/dash rendering
  Car.gd                 swaps between placeholder shape and an assigned texture
```

## Roadmap

- Drop in real sprites for cars and road (see "Adding your own art" above)
- More competitive mini-modes beyond "don't crash" (time attack, reverse traffic, narrowing lanes, item pickups, etc.)
- Gamepad support
- Export to web (HTML5) and/or desktop builds

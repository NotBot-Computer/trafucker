# Traffic Tower

A local split-screen party game: dodge oncoming traffic, don't crash, and outlast your friends. Styled after retro top-down pixel racers, with a "many small competitive modes" structure inspired by *Tricky Towers*.

Built in **Godot 4**.

## Current mode

**Don't Crash** — steer between lanes, avoid traffic, survive as long as possible. Speed ramps up over time. Whoever covers the most distance before crashing wins the round.

## Controls

| Player | Left | Right |
| ------ | ---- | ----- |
| P1     | A    | D     |
| P2     | ←    | →     |

Press **Enter** to restart after a round ends.

## Running it

Open the project folder in the Godot 4 editor (`godot --path .` from this directory, or `Import` from the project manager), then press **F5** / the Play button.

## Adding your own art

Every car (`scenes/Car.tscn`) has an empty `Sprite2D` child. Open it in the editor and drag a PNG onto the Sprite2D's **Texture** property in the Inspector — no code changes needed. The placeholder shape (a colored `Polygon2D`) automatically hides once a texture is assigned. `Car.gd` scales whatever texture you provide to the car's collision size.

## Project structure

```
project.godot
scenes/
  Main.tscn         two PlayerBoards side by side, round state, restart UI
  PlayerBoard.tscn   one player's road + car + obstacle spawner
  Car.tscn          sprite/placeholder + collision, reused for player and traffic
scripts/
  Main.gd
  PlayerBoard.gd     steering physics, spawning, scoring, collision handling
  Road.gd            lane math and road/dash rendering
  Car.gd             swaps between placeholder shape and an assigned texture
```

## Roadmap

- Drop in real sprites for cars and road (see "Adding your own art" above)
- More competitive mini-modes beyond "don't crash" (time attack, reverse traffic, narrowing lanes, item pickups, etc.)
- More players (3-4 way split-screen)
- Gamepad support
- Export to web (HTML5) and/or desktop builds

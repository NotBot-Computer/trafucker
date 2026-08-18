# Traffic Tower

A local split-screen party game: dodge oncoming traffic, don't crash, and outlast your friends. Built for browser/PC, styled after retro top-down pixel racers, with a "many small competitive modes" structure inspired by *Tricky Towers*.

## Current mode

**Don't Crash** — steer between lanes, avoid traffic, survive as long as possible. Speed ramps up over time. Last car standing (or furthest distance) wins the round.

## Controls

| Player | Left | Right |
| ------ | ---- | ----- |
| P1     | A    | D     |
| P2     | ←    | →     |

Press **Enter** to restart after a round ends.

## Running locally

```bash
npm install
npm run dev
```

## Project structure

```
src/
  main.ts              entry point
  style.css            HUD/page chrome styling
  game/
    Game.ts            orchestrates boards, input, resize, round state
    InputManager.ts     keyboard state with edge-detection
    PlayerBoard.ts      one player's simulation: steering, spawning, collision
    types.ts            shared interfaces
    entities/
      Car.ts           car sprites, palettes, drawing
      Road.ts          lane math and road/dash rendering
```

## Roadmap

- More competitive mini-modes beyond "don't crash" (time attack, reverse traffic, narrowing lanes, item pickups, etc.)
- More players (3-4 way split-screen)
- Gamepad support
- Persistent best scores
- Deploy to Cloudflare Pages

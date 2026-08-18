import { InputManager } from "./InputManager";
import { PlayerBoard } from "./PlayerBoard";
import type { PlayerConfig } from "./types";

const BOARD_GAP = 6;
const BASE_HEIGHT = 620;

const PLAYER_CONFIGS: PlayerConfig[] = [
  {
    id: 1,
    name: "P1",
    color: "#3b6fe0",
    darkColor: "#22408c",
    keys: { left: "a", right: "d" },
  },
  {
    id: 2,
    name: "P2",
    color: "#e0473b",
    darkColor: "#8c2318",
    keys: { left: "ArrowLeft", right: "ArrowRight" },
  },
];

type GameState = "playing" | "gameover";

export class Game {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private input = new InputManager();
  private boards: PlayerBoard[];
  private state: GameState = "playing";
  private lastTime = 0;
  private statusEl: HTMLElement;
  private overlayEl: HTMLElement;
  private overlayTitleEl: HTMLElement;
  private overlayBodyEl: HTMLElement;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas 2D context not available");
    this.ctx = ctx;
    this.boards = PLAYER_CONFIGS.map((cfg) => new PlayerBoard(cfg));

    this.statusEl = document.getElementById("status-line")!;
    this.overlayEl = document.getElementById("overlay")!;
    this.overlayTitleEl = document.getElementById("overlay-title")!;
    this.overlayBodyEl = document.getElementById("overlay-body")!;

    this.renderStatusLine();
    window.addEventListener("resize", () => this.resize());
    this.resize();

    window.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && this.state === "gameover") {
        this.restart();
      }
    });
  }

  private static keyLabel(key: string): string {
    if (key === "ArrowLeft") return "←";
    if (key === "ArrowRight") return "→";
    return key.toUpperCase();
  }

  private renderStatusLine(): void {
    this.statusEl.innerHTML = this.boards
      .map(
        (b) =>
          `<span style="color:${b.config.color}">${b.config.name}: ${Game.keyLabel(b.config.keys.left)} / ${Game.keyLabel(b.config.keys.right)}</span>`,
      )
      .join("");
  }

  private resize(): void {
    const cssWidth = this.canvas.clientWidth || this.canvas.parentElement!.clientWidth;
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.floor(cssWidth * dpr);
    this.canvas.height = Math.floor(BASE_HEIGHT * dpr);
    this.canvas.style.height = `${BASE_HEIGHT}px`;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  start(): void {
    requestAnimationFrame((t) => this.loop(t));
  }

  private restart(): void {
    for (const b of this.boards) b.reset();
    this.state = "playing";
    this.overlayEl.classList.add("hidden");
  }

  private loop(time: number): void {
    const dt = this.lastTime ? Math.min(0.05, (time - this.lastTime) / 1000) : 0;
    this.lastTime = time;

    if (this.state === "playing") {
      this.update(dt);
    }
    this.render();
    this.input.endFrame();

    requestAnimationFrame((t) => this.loop(t));
  }

  private update(dt: number): void {
    const width = this.canvas.clientWidth;
    const height = BASE_HEIGHT;
    const boardWidth = (width - BOARD_GAP * (this.boards.length - 1)) / this.boards.length;

    for (const board of this.boards) {
      board.update(dt, this.input, boardWidth, height);
    }

    if (this.boards.every((b) => !b.alive)) {
      this.endRound();
    }
  }

  private endRound(): void {
    this.state = "gameover";
    const results = this.boards.map((b) => b.result);
    const winner = results.reduce((a, b) => (b.distance > a.distance ? b : a));

    this.overlayTitleEl.textContent = `${winner.name} WINS`;
    this.overlayBodyEl.textContent = results
      .map((r) => `${r.name}: ${r.distance}m in ${r.survivedSeconds.toFixed(1)}s`)
      .join("\n");
    this.overlayEl.classList.remove("hidden");
  }

  private render(): void {
    const width = this.canvas.clientWidth;
    const height = BASE_HEIGHT;
    this.ctx.clearRect(0, 0, width, height);

    let x = 0;
    const boardWidth = (width - BOARD_GAP * (this.boards.length - 1)) / this.boards.length;
    for (const board of this.boards) {
      board.render(this.ctx, x, 0, boardWidth, height);
      x += boardWidth + BOARD_GAP;
    }
  }
}

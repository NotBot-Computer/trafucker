import { InputManager } from "./InputManager";
import type { PlayerConfig, PlayerResult } from "./types";

interface Obstacle {
  lane: number;
  y: number;
  color: string;
  darkColor: string;
}

const LANE_COUNT = 3;
const CAR_WIDTH_RATIO = 0.22;
const CAR_HEIGHT_RATIO = 0.14;
const BASE_SPEED = 160;
const SPEED_PER_SECOND = 6;
const SPAWN_INTERVAL_START = 1.1;
const SPAWN_INTERVAL_MIN = 0.45;
const LANE_LERP_SPEED = 12;

const OBSTACLE_PALETTE: Array<{ color: string; darkColor: string }> = [
  { color: "#e2e2e2", darkColor: "#9c9c9c" },
  { color: "#2c2c2c", darkColor: "#111111" },
  { color: "#c0392b", darkColor: "#7b241c" },
  { color: "#5d6d7e", darkColor: "#34495e" },
];

export class PlayerBoard {
  config: PlayerConfig;
  private laneIndex = Math.floor(LANE_COUNT / 2);
  private targetLaneIndex = this.laneIndex;
  private carX = 0;
  private obstacles: Obstacle[] = [];
  private spawnTimer = 0;
  private elapsed = 0;
  private distance = 0;
  alive = true;
  private crashFlashTimer = 0;

  constructor(config: PlayerConfig) {
    this.config = config;
  }

  reset(): void {
    this.laneIndex = Math.floor(LANE_COUNT / 2);
    this.targetLaneIndex = this.laneIndex;
    this.obstacles = [];
    this.spawnTimer = 0;
    this.elapsed = 0;
    this.distance = 0;
    this.alive = true;
    this.crashFlashTimer = 0;
  }

  get result(): PlayerResult {
    return {
      name: this.config.name,
      distance: Math.floor(this.distance),
      survivedSeconds: this.elapsed,
      alive: this.alive,
    };
  }

  private currentSpeed(): number {
    return BASE_SPEED + this.elapsed * SPEED_PER_SECOND;
  }

  private spawnInterval(): number {
    return Math.max(
      SPAWN_INTERVAL_MIN,
      SPAWN_INTERVAL_START - this.elapsed * 0.02,
    );
  }

  update(dt: number, input: InputManager, width: number, height: number): void {
    if (!this.alive) {
      this.crashFlashTimer += dt;
      return;
    }

    if (input.wasPressed(this.config.keys.left)) {
      this.targetLaneIndex = Math.max(0, this.targetLaneIndex - 1);
    }
    if (input.wasPressed(this.config.keys.right)) {
      this.targetLaneIndex = Math.min(LANE_COUNT - 1, this.targetLaneIndex + 1);
    }
    this.laneIndex += (this.targetLaneIndex - this.laneIndex) * Math.min(1, LANE_LERP_SPEED * dt);

    this.elapsed += dt;
    const speed = this.currentSpeed();
    this.distance += speed * dt;

    this.spawnTimer -= dt;
    if (this.spawnTimer <= 0) {
      this.spawnTimer = this.spawnInterval();
      this.spawnObstacle();
    }

    for (const obstacle of this.obstacles) {
      obstacle.y += speed * dt;
    }
    this.obstacles = this.obstacles.filter((o) => o.y < height + 80);

    this.carX = this.laneCenterX(this.laneIndex, width);
    this.checkCollision(width, height);
  }

  private spawnObstacle(): void {
    const usedLanes = this.obstacles
      .filter((o) => o.y < 140)
      .map((o) => o.lane);
    const availableLanes = Array.from({ length: LANE_COUNT }, (_, i) => i).filter(
      (lane) => !usedLanes.includes(lane),
    );
    if (availableLanes.length === 0) return;
    const lane = availableLanes[Math.floor(Math.random() * availableLanes.length)];
    const palette =
      OBSTACLE_PALETTE[Math.floor(Math.random() * OBSTACLE_PALETTE.length)];
    this.obstacles.push({ lane, y: -120, color: palette.color, darkColor: palette.darkColor });
  }

  private laneCenterX(lane: number, width: number): number {
    const laneWidth = width / LANE_COUNT;
    return laneWidth * lane + laneWidth / 2;
  }

  private checkCollision(width: number, height: number): void {
    const carW = width * CAR_WIDTH_RATIO;
    const carH = height * CAR_HEIGHT_RATIO;
    const carY = height - carH - 24;
    const carLeft = this.carX - carW / 2;
    const carRight = this.carX + carW / 2;

    for (const obstacle of this.obstacles) {
      const ox = this.laneCenterX(obstacle.lane, width);
      const oLeft = ox - carW / 2;
      const oRight = ox + carW / 2;
      const oTop = obstacle.y;
      const oBottom = obstacle.y + carH;
      const overlapsX = carLeft < oRight && carRight > oLeft;
      const overlapsY = carY < oBottom && carY + carH > oTop;
      if (overlapsX && overlapsY) {
        this.alive = false;
        break;
      }
    }
  }

  render(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number): void {
    ctx.save();
    ctx.translate(x, y);
    ctx.beginPath();
    ctx.rect(0, 0, width, height);
    ctx.clip();

    this.renderRoad(ctx, width, height);

    for (const obstacle of this.obstacles) {
      this.renderCar(
        ctx,
        this.laneCenterX(obstacle.lane, width),
        obstacle.y,
        width,
        height,
        obstacle.color,
        obstacle.darkColor,
      );
    }

    const carH = height * CAR_HEIGHT_RATIO;
    const carY = height - carH - 24;
    ctx.globalAlpha = this.alive ? 1 : 0.35;
    this.renderCar(ctx, this.carX, carY, width, height, this.config.color, this.config.darkColor);
    ctx.globalAlpha = 1;

    if (!this.alive) {
      ctx.fillStyle = "rgba(20, 10, 10, 0.55)";
      ctx.fillRect(0, 0, width, height);
      ctx.fillStyle = "#ff5555";
      ctx.font = `bold ${Math.floor(width * 0.09)}px "Press Start 2P", monospace`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("CRASH", width / 2, height / 2);
    }

    ctx.restore();
  }

  private renderRoad(ctx: CanvasRenderingContext2D, width: number, height: number): void {
    const shoulderW = width * 0.06;
    ctx.fillStyle = "#5c7a3c";
    ctx.fillRect(0, 0, width, height);
    ctx.fillStyle = "#8a8f98";
    ctx.fillRect(shoulderW, 0, width - shoulderW * 2, height);

    const roadW = width - shoulderW * 2;
    const laneW = roadW / LANE_COUNT;
    const dashLen = 26;
    const gapLen = 22;
    const offset = (this.distance * 0.5) % (dashLen + gapLen);

    ctx.strokeStyle = "#f2f2f2";
    ctx.lineWidth = Math.max(2, width * 0.012);
    for (let lane = 1; lane < LANE_COUNT; lane++) {
      const lx = shoulderW + laneW * lane;
      ctx.beginPath();
      for (let dy = -dashLen; dy < height + dashLen; dy += dashLen + gapLen) {
        const yy = dy + offset;
        ctx.moveTo(lx, yy);
        ctx.lineTo(lx, yy + dashLen);
      }
      ctx.stroke();
    }

    ctx.fillStyle = "#3a3f33";
    for (let i = 0; i < 6; i++) {
      const gy = ((i * 130 + offset * 2) % (height + 60)) - 30;
      ctx.fillRect(shoulderW * 0.3, gy, shoulderW * 0.4, 18);
      ctx.fillRect(width - shoulderW * 0.7, gy + 40, shoulderW * 0.4, 18);
    }
  }

  private renderCar(
    ctx: CanvasRenderingContext2D,
    cx: number,
    topY: number,
    width: number,
    _height: number,
    color: string,
    darkColor: string,
  ): void {
    const w = width * CAR_WIDTH_RATIO;
    const h = width * CAR_WIDTH_RATIO * 1.7;
    const x = cx - w / 2;
    const y = topY;

    ctx.fillStyle = "rgba(0,0,0,0.25)";
    ctx.fillRect(x + 3, y + 4, w, h);

    ctx.fillStyle = color;
    ctx.fillRect(x, y, w, h);

    ctx.fillStyle = darkColor;
    ctx.fillRect(x + w * 0.12, y + h * 0.14, w * 0.76, h * 0.24);
    ctx.fillRect(x + w * 0.12, y + h * 0.62, w * 0.76, h * 0.24);

    ctx.strokeStyle = "rgba(0,0,0,0.35)";
    ctx.lineWidth = 2;
    ctx.strokeRect(x, y, w, h);
  }
}

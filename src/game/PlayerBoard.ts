import { InputManager } from "./InputManager";
import type { PlayerConfig, PlayerResult } from "./types";

interface Obstacle {
  lane: number;
  y: number;
  color: string;
  darkColor: string;
}

interface DriftMark {
  x: number;
  y: number;
  age: number;
}

const LANE_COUNT = 3;
const CAR_WIDTH_RATIO = 0.22;
const CAR_HEIGHT_RATIO = 0.14;
const BASE_SPEED = 160;
const SPEED_PER_SECOND = 6;
const SPAWN_INTERVAL_START = 1.1;
const SPAWN_INTERVAL_MIN = 0.45;

const MAX_STEER_SPEED = 460; // px/s, lateral top speed
const STEER_RESPONSE = 9; // higher = snappier approach to target velocity
const MAX_TILT = 0.32; // radians, car banking when steering
const DRIFT_MARK_LIFETIME = 0.4;
const CRASH_SHAKE_DURATION = 0.25;

const OBSTACLE_PALETTE: Array<{ color: string; darkColor: string }> = [
  { color: "#e2e2e2", darkColor: "#9c9c9c" },
  { color: "#2c2c2c", darkColor: "#111111" },
  { color: "#c0392b", darkColor: "#7b241c" },
  { color: "#5d6d7e", darkColor: "#34495e" },
];

export class PlayerBoard {
  config: PlayerConfig;
  private carX = 0;
  private carVX = 0;
  private tilt = 0;
  private driftMarks: DriftMark[] = [];
  private obstacles: Obstacle[] = [];
  private spawnTimer = 0;
  private elapsed = 0;
  private distance = 0;
  alive = true;
  private crashFlashTimer = 0;
  private initialized = false;

  constructor(config: PlayerConfig) {
    this.config = config;
  }

  reset(): void {
    this.carVX = 0;
    this.tilt = 0;
    this.driftMarks = [];
    this.obstacles = [];
    this.spawnTimer = 0;
    this.elapsed = 0;
    this.distance = 0;
    this.alive = true;
    this.crashFlashTimer = 0;
    this.initialized = false;
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
    if (!this.initialized) {
      this.carX = width / 2;
      this.initialized = true;
    }

    if (!this.alive) {
      this.crashFlashTimer += dt;
      return;
    }

    const left = input.isHeld(this.config.keys.left);
    const right = input.isHeld(this.config.keys.right);
    const targetVX = left && !right ? -MAX_STEER_SPEED : right && !left ? MAX_STEER_SPEED : 0;
    const approach = 1 - Math.exp(-STEER_RESPONSE * dt);
    this.carVX += (targetVX - this.carVX) * approach;

    const shoulderW = width * 0.06;
    const carW = width * CAR_WIDTH_RATIO;
    const minX = shoulderW + carW / 2;
    const maxX = width - shoulderW - carW / 2;
    const nextX = this.carX + this.carVX * dt;
    if (nextX < minX) {
      this.carX = minX;
      this.carVX = 0;
    } else if (nextX > maxX) {
      this.carX = maxX;
      this.carVX = 0;
    } else {
      this.carX = nextX;
    }

    this.tilt = Math.max(-1, Math.min(1, this.carVX / MAX_STEER_SPEED)) * MAX_TILT;

    if (Math.abs(this.carVX) > MAX_STEER_SPEED * 0.6) {
      const carH = height * CAR_HEIGHT_RATIO;
      this.driftMarks.push({ x: this.carX, y: height - 24 - carH * 0.15, age: 0 });
    }
    for (const mark of this.driftMarks) mark.age += dt;
    this.driftMarks = this.driftMarks.filter((m) => m.age < DRIFT_MARK_LIFETIME);

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
    const shrink = carW * 0.15;
    const carLeft = this.carX - carW / 2 + shrink;
    const carRight = this.carX + carW / 2 - shrink;

    for (const obstacle of this.obstacles) {
      const ox = this.laneCenterX(obstacle.lane, width);
      const oLeft = ox - carW / 2 + shrink;
      const oRight = ox + carW / 2 - shrink;
      const oTop = obstacle.y;
      const oBottom = obstacle.y + carH;
      const overlapsX = carLeft < oRight && carRight > oLeft;
      const overlapsY = carY < oBottom && carY + carH > oTop;
      if (overlapsX && overlapsY) {
        this.alive = false;
        this.crashFlashTimer = 0;
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

    if (!this.alive && this.crashFlashTimer < CRASH_SHAKE_DURATION) {
      const shake = (1 - this.crashFlashTimer / CRASH_SHAKE_DURATION) * 6;
      ctx.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake);
    }

    this.renderRoad(ctx, width, height);

    for (const mark of this.driftMarks) {
      const alpha = 1 - mark.age / DRIFT_MARK_LIFETIME;
      ctx.fillStyle = `rgba(20,20,20,${alpha * 0.3})`;
      ctx.fillRect(mark.x - 3, mark.y, 3, 10);
    }

    for (const obstacle of this.obstacles) {
      this.renderCar(
        ctx,
        this.laneCenterX(obstacle.lane, width),
        obstacle.y,
        width,
        obstacle.color,
        obstacle.darkColor,
        0,
      );
    }

    const carH = height * CAR_HEIGHT_RATIO;
    const carY = height - carH - 24;
    ctx.globalAlpha = this.alive ? 1 : 0.35;
    this.renderCar(ctx, this.carX, carY, width, this.config.color, this.config.darkColor, this.tilt);
    ctx.globalAlpha = 1;

    if (!this.alive && this.crashFlashTimer < 0.15) {
      ctx.fillStyle = `rgba(255,255,255,${(1 - this.crashFlashTimer / 0.15) * 0.7})`;
      ctx.fillRect(0, 0, width, height);
    }

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
    color: string,
    darkColor: string,
    tilt: number,
  ): void {
    const w = width * CAR_WIDTH_RATIO;
    const h = width * CAR_WIDTH_RATIO * 1.7;
    const cy = topY + h / 2;

    ctx.save();
    ctx.translate(cx, cy);
    if (tilt !== 0) ctx.rotate(tilt);

    ctx.fillStyle = "rgba(0,0,0,0.25)";
    ctx.fillRect(-w / 2 + 3, -h / 2 + 4, w, h);

    ctx.fillStyle = color;
    ctx.fillRect(-w / 2, -h / 2, w, h);

    ctx.fillStyle = darkColor;
    ctx.fillRect(-w / 2 + w * 0.12, -h / 2 + h * 0.14, w * 0.76, h * 0.24);
    ctx.fillRect(-w / 2 + w * 0.12, -h / 2 + h * 0.62, w * 0.76, h * 0.24);

    ctx.strokeStyle = "rgba(0,0,0,0.35)";
    ctx.lineWidth = 2;
    ctx.strokeRect(-w / 2, -h / 2, w, h);

    ctx.restore();
  }
}

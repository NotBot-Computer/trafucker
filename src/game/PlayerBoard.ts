import { InputManager } from "./InputManager";
import type { PlayerConfig, PlayerResult } from "./types";
import { TAILLIGHT, type CarSprite, carSize, drawCar, pickRandomCarSprite } from "./entities/Car";
import { drawRoad, laneCenterX, roadMetrics } from "./entities/Road";

interface Obstacle {
  lane: number;
  y: number;
  sprite: CarSprite;
}

interface DriftMark {
  x: number;
  y: number;
  age: number;
}

const LANE_COUNT = 5;
const BASE_SPEED = 160;
const SPEED_PER_SECOND = 6;
const SPAWN_INTERVAL_START = 0.85;
const SPAWN_INTERVAL_MIN = 0.35;
const SPAWN_LANE_CLEAR_Y = 190;

const MAX_STEER_SPEED = 460; // px/s, lateral top speed
const STEER_RESPONSE = 9; // higher = snappier approach to target velocity
const MAX_TILT = 0.32; // radians, car banking when steering
const DRIFT_MARK_LIFETIME = 0.4;
const CRASH_SHAKE_DURATION = 0.25;

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
      SPAWN_INTERVAL_START - this.elapsed * 0.015,
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

    const metrics = roadMetrics(width, LANE_COUNT);
    const playerSize = carSize(metrics.laneW, "sedan");

    const left = input.isHeld(this.config.keys.left);
    const right = input.isHeld(this.config.keys.right);
    const targetVX = left && !right ? -MAX_STEER_SPEED : right && !left ? MAX_STEER_SPEED : 0;
    const approach = 1 - Math.exp(-STEER_RESPONSE * dt);
    this.carVX += (targetVX - this.carVX) * approach;

    const minX = metrics.shoulderW + playerSize.w / 2;
    const maxX = width - metrics.shoulderW - playerSize.w / 2;
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
      this.driftMarks.push({ x: this.carX, y: height - 24 - playerSize.h * 0.15, age: 0 });
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
    this.obstacles = this.obstacles.filter((o) => o.y < height + 140);

    this.checkCollision(width, height);
  }

  private spawnObstacle(): void {
    const usedLanes = this.obstacles
      .filter((o) => o.y < SPAWN_LANE_CLEAR_Y)
      .map((o) => o.lane);
    const availableLanes = Array.from({ length: LANE_COUNT }, (_, i) => i).filter(
      (lane) => !usedLanes.includes(lane),
    );
    if (availableLanes.length === 0) return;
    const lane = availableLanes[Math.floor(Math.random() * availableLanes.length)];
    this.obstacles.push({ lane, y: -160, sprite: pickRandomCarSprite() });
  }

  private checkCollision(width: number, height: number): void {
    const metrics = roadMetrics(width, LANE_COUNT);
    const playerSize = carSize(metrics.laneW, "sedan");
    const shrink = playerSize.w * 0.15;
    const carY = height - playerSize.h - 24;
    const carLeft = this.carX - playerSize.w / 2 + shrink;
    const carRight = this.carX + playerSize.w / 2 - shrink;

    for (const obstacle of this.obstacles) {
      const oSize = carSize(metrics.laneW, obstacle.sprite.kind);
      const ox = laneCenterX(obstacle.lane, metrics);
      const oLeft = ox - oSize.w / 2 + shrink;
      const oRight = ox + oSize.w / 2 - shrink;
      const oTop = obstacle.y;
      const oBottom = obstacle.y + oSize.h;
      const overlapsX = carLeft < oRight && carRight > oLeft;
      const overlapsY = carY < oBottom && carY + playerSize.h > oTop;
      if (overlapsX && overlapsY) {
        this.alive = false;
        this.crashFlashTimer = 0;
        break;
      }
    }
  }

  render(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number): void {
    const metrics = roadMetrics(width, LANE_COUNT);
    const playerSize = carSize(metrics.laneW, "sedan");
    const playerSprite: CarSprite = {
      kind: "sedan",
      color: this.config.color,
      darkColor: this.config.darkColor,
      accent: TAILLIGHT,
    };

    ctx.save();
    ctx.translate(x, y);
    ctx.beginPath();
    ctx.rect(0, 0, width, height);
    ctx.clip();

    if (!this.alive && this.crashFlashTimer < CRASH_SHAKE_DURATION) {
      const shake = (1 - this.crashFlashTimer / CRASH_SHAKE_DURATION) * 6;
      ctx.translate((Math.random() - 0.5) * shake, (Math.random() - 0.5) * shake);
    }

    drawRoad(ctx, width, height, LANE_COUNT, this.distance);

    for (const mark of this.driftMarks) {
      const alpha = 1 - mark.age / DRIFT_MARK_LIFETIME;
      ctx.fillStyle = `rgba(20,20,20,${alpha * 0.3})`;
      ctx.fillRect(mark.x - 3, mark.y, 3, 10);
    }

    for (const obstacle of this.obstacles) {
      drawCar(ctx, laneCenterX(obstacle.lane, metrics), obstacle.y, metrics.laneW, obstacle.sprite);
    }

    const carY = height - playerSize.h - 24;
    ctx.globalAlpha = this.alive ? 1 : 0.35;
    drawCar(ctx, this.carX, carY, metrics.laneW, playerSprite, this.tilt);
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
}

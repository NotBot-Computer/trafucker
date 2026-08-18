export interface RoadMetrics {
  shoulderW: number;
  roadW: number;
  laneW: number;
}

const SHOULDER_RATIO = 0.06;

export function roadMetrics(width: number, laneCount: number): RoadMetrics {
  const shoulderW = width * SHOULDER_RATIO;
  const roadW = width - shoulderW * 2;
  return { shoulderW, roadW, laneW: roadW / laneCount };
}

export function laneCenterX(lane: number, metrics: RoadMetrics): number {
  return metrics.shoulderW + metrics.laneW * lane + metrics.laneW / 2;
}

export function drawRoad(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  laneCount: number,
  scrollDistance: number,
): void {
  const { shoulderW, laneW } = roadMetrics(width, laneCount);

  ctx.fillStyle = "#5c7a3c";
  ctx.fillRect(0, 0, width, height);
  ctx.fillStyle = "#8a8f98";
  ctx.fillRect(shoulderW, 0, width - shoulderW * 2, height);

  const dashLen = 22;
  const gapLen = 18;
  const offset = (scrollDistance * 0.5) % (dashLen + gapLen);

  ctx.strokeStyle = "#f2f2f2";
  ctx.lineWidth = Math.max(2, width * 0.01);
  for (let lane = 1; lane < laneCount; lane++) {
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

export type CarKind = "sedan" | "truck";

export interface CarSprite {
  kind: CarKind;
  color: string;
  darkColor: string;
  accent: string;
}

const SEDAN_PALETTE: Array<Omit<CarSprite, "kind" | "accent">> = [
  { color: "#e9e9e9", darkColor: "#b0b0b0" },
  { color: "#2b2b2b", darkColor: "#131313" },
  { color: "#c7ccd1", darkColor: "#8b9096" },
  { color: "#5d6d7e", darkColor: "#34495e" },
  { color: "#c9a66b", darkColor: "#8a6d3b" },
  { color: "#7a2e2e", darkColor: "#4a1a1a" },
];

const TRUCK_PALETTE: Array<Omit<CarSprite, "kind">> = [
  { color: "#eeeeee", darkColor: "#9c9c9c", accent: "#b23b3b" },
  { color: "#d8d3c4", darkColor: "#9a9484", accent: "#c98a2c" },
  { color: "#cfd6dc", darkColor: "#8f98a1", accent: "#b23b3b" },
];

const TRUCK_CHANCE = 0.25;

export function pickRandomCarSprite(): CarSprite {
  if (Math.random() < TRUCK_CHANCE) {
    const preset = TRUCK_PALETTE[Math.floor(Math.random() * TRUCK_PALETTE.length)];
    return { kind: "truck", ...preset };
  }
  const preset = SEDAN_PALETTE[Math.floor(Math.random() * SEDAN_PALETTE.length)];
  return { kind: "sedan", accent: preset.darkColor, ...preset };
}

export function carSize(laneWidth: number, kind: CarKind): { w: number; h: number } {
  if (kind === "truck") {
    const w = laneWidth * 0.56;
    return { w, h: w * 2.6 };
  }
  const w = laneWidth * 0.62;
  return { w, h: w * 1.7 };
}

/** Draws a car centered horizontally at cx, with its top edge at topY. */
export function drawCar(
  ctx: CanvasRenderingContext2D,
  cx: number,
  topY: number,
  laneWidth: number,
  sprite: CarSprite,
  tilt = 0,
): void {
  const { w, h } = carSize(laneWidth, sprite.kind);
  const cy = topY + h / 2;

  ctx.save();
  ctx.translate(cx, cy);
  if (tilt !== 0) ctx.rotate(tilt);

  ctx.fillStyle = "rgba(0,0,0,0.25)";
  ctx.fillRect(-w / 2 + 2, -h / 2 + 3, w, h);

  ctx.fillStyle = sprite.color;
  ctx.fillRect(-w / 2, -h / 2, w, h);

  if (sprite.kind === "truck") {
    ctx.fillStyle = sprite.darkColor;
    ctx.fillRect(-w / 2 + w * 0.14, -h / 2 + h * 0.08, w * 0.72, h * 0.18);
    ctx.fillStyle = sprite.accent;
    ctx.fillRect(-w / 2 + w * 0.08, h / 2 - h * 0.14, w * 0.84, h * 0.1);
  } else {
    ctx.fillStyle = sprite.darkColor;
    ctx.fillRect(-w / 2 + w * 0.12, -h / 2 + h * 0.14, w * 0.76, h * 0.24);
    ctx.fillRect(-w / 2 + w * 0.12, -h / 2 + h * 0.62, w * 0.76, h * 0.24);
  }

  ctx.strokeStyle = "rgba(0,0,0,0.35)";
  ctx.lineWidth = 1.5;
  ctx.strokeRect(-w / 2, -h / 2, w, h);

  ctx.restore();
}

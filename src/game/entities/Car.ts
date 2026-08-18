export type CarKind = "sedan" | "truck";

export interface CarSprite {
  kind: CarKind;
  color: string;
  darkColor: string;
  accent: string;
}

export const TAILLIGHT = "#c0392b";
const HEADLIGHT = "#fff3b8";
const GLASS = "#8fa6b3";
const GLASS_GLINT = "#d9e8ee";
const WHEEL = "#181818";
const MIRROR = "#202020";

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
  return { kind: "sedan", accent: TAILLIGHT, ...preset };
}

export function carSize(laneWidth: number, kind: CarKind): { w: number; h: number } {
  if (kind === "truck") {
    const w = laneWidth * 0.56;
    return { w, h: w * 2.6 };
  }
  const w = laneWidth * 0.62;
  return { w, h: w * 1.7 };
}

// Pixel-grid templates: top-down car, front at row 0. Each string is one row,
// each character one "pixel" cell. '.' is transparent (creates the rounded
// silhouette); other letters map to a color role in buildColorMap().
// B=body  H=hood/roof highlight  S=shade  W=glass  w=glass glint
// K=wheel  M=mirror  Y=headlight  R=taillight
const SEDAN_TEMPLATE = [
  "...BBBBB...",
  "..BBBBBBB..",
  ".YBBBHBBBY.",
  "KBBBBHBBBBK",
  "MBBBBHBBBBM",
  ".WwWWWWWWW.",
  ".WWWWWWWWW.",
  ".WWWWWWWWW.",
  ".SSSSSSSSS.",
  ".BBBBHBBBB.",
  ".BBBBHBBBB.",
  ".BBBBHBBBB.",
  ".BBBBHBBBB.",
  ".SSSSSSSSS.",
  ".WWWwWWWWW.",
  ".WWWWWWWWW.",
  "KRBBBHBBBRK",
  "...BBBBB...",
];

const TRUCK_TEMPLATE = [
  "...BBBBB...",
  "..BBBBBBB..",
  ".YBBBHBBBY.",
  "KBBBBHBBBBK",
  "MBBBBHBBBBM",
  ".WwWWWWWWW.",
  ".WWWWWWWWW.",
  ".SSSSSSSSS.",
  ".BBBBHBBBB.",
  ".BBBBHBBBB.",
  "KBBBBHBBBBK",
  "KBBBBHBBBBK",
  ".BBBBHBBBB.",
  ".BBBBHBBBB.",
  ".SSSSSSSSS.",
  ".BBBBHBBBB.",
  ".BBBBHBBBB.",
  "KBBBBHBBBBK",
  "KBBBBHBBBBK",
  ".BBBBHBBBB.",
  ".BBBBHBBBB.",
  ".SSSSSSSSS.",
  "KRBBBHBBBRK",
  ".SSSSSSSSS.",
  "...BBBBB...",
];

function lighten(hex: string, amount: number): string {
  const clean = hex.replace("#", "");
  const full = clean.length === 3 ? clean.split("").map((c) => c + c).join("") : clean;
  const num = parseInt(full, 16);
  const r = Math.round(((num >> 16) & 255) + (255 - ((num >> 16) & 255)) * amount);
  const g = Math.round(((num >> 8) & 255) + (255 - ((num >> 8) & 255)) * amount);
  const b = Math.round((num & 255) + (255 - (num & 255)) * amount);
  return `rgb(${r},${g},${b})`;
}

function buildColorMap(sprite: CarSprite): Record<string, string> {
  return {
    B: sprite.color,
    H: lighten(sprite.color, 0.35),
    S: sprite.darkColor,
    W: GLASS,
    w: GLASS_GLINT,
    K: WHEEL,
    M: MIRROR,
    Y: HEADLIGHT,
    R: sprite.accent,
  };
}

function templateFor(kind: CarKind): string[] {
  return kind === "truck" ? TRUCK_TEMPLATE : SEDAN_TEMPLATE;
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
  const template = templateFor(sprite.kind);
  const rows = template.length;
  const cols = template[0].length;
  const cellW = w / cols;
  const cellH = h / rows;
  const colorMap = buildColorMap(sprite);

  const at = (r: number, c: number): string =>
    r < 0 || r >= rows || c < 0 || c >= cols ? "." : template[r][c];

  ctx.save();
  ctx.translate(cx, topY + h / 2);
  if (tilt !== 0) ctx.rotate(tilt);
  ctx.translate(-w / 2, -h / 2);

  // Soft ground shadow, offset slightly, matching the sprite silhouette.
  ctx.fillStyle = "rgba(0,0,0,0.28)";
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (template[r][c] === ".") continue;
      ctx.fillRect(c * cellW + 2, r * cellH + 3, cellW + 0.6, cellH + 0.6);
    }
  }

  // Fill pass.
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const ch = template[r][c];
      if (ch === ".") continue;
      ctx.fillStyle = colorMap[ch] ?? sprite.color;
      ctx.fillRect(c * cellW, r * cellH, cellW + 0.6, cellH + 0.6);
    }
  }

  // Outline pass: darken any edge of a filled cell that borders empty space,
  // so the silhouette reads as one clean shape instead of a grid of squares.
  const outline = Math.max(1, Math.min(cellW, cellH) * 0.22);
  ctx.fillStyle = "rgba(10,10,10,0.55)";
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (template[r][c] === ".") continue;
      const x = c * cellW;
      const y = r * cellH;
      if (at(r - 1, c) === ".") ctx.fillRect(x, y, cellW + 0.6, outline);
      if (at(r + 1, c) === ".") ctx.fillRect(x, y + cellH - outline, cellW + 0.6, outline);
      if (at(r, c - 1) === ".") ctx.fillRect(x, y, outline, cellH + 0.6);
      if (at(r, c + 1) === ".") ctx.fillRect(x + cellW - outline, y, outline, cellH + 0.6);
    }
  }

  ctx.restore();
}

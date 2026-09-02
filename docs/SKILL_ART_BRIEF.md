# Skill art brief — what to generate, and where it goes

Every piece of art the six modular skills (`scripts/skills/`) use today is a
**placeholder**: `scripts/dev/make_placeholder_skill_icons.py` draws them from
hand-typed 16x16 pixel maps because no image generator was reachable from the
session that built the skills. This file is the brief for replacing them, per
skill, plus the conventions that any sheet for this project has to follow —
most of which were learned the hard way and are recorded in
`docs/PROJECT_STATE.md` (§7 and §5 sessions G/H/P/V/W).

## Conventions that apply to every asset

- **Real alpha channel.** Export PNG with transparency. Three of the sheets
  this project was given had none (`tank.png`'s checkerboard was baked into
  the RGB; `patlama.png` and all three Nitro sheets were flat `RGB`), and each
  one cost a session a background-removal pass. Ask for "transparent
  background, PNG with alpha", and check with `python3 -c "from PIL import
  Image; print(Image.open('x.png').mode)"` — it must say `RGBA`.
- **Up is forward.** Godot 2D has +y down; in this game traffic scrolls toward
  +y and "ahead" is -y, so anything with a direction of travel is drawn nose-up
  (all the car sprites are).
- **Pixel art, hard edges, no anti-aliasing at the silhouette.** The heart pip
  (`sprites/ui/heart.png`) is the reference: an 18px sprite with a 1px dark
  outline, a flat body colour and one highlight. Icons are drawn at the sizes
  below and scaled *up* in-game with linear filtering, which is what the rest
  of the art already does.
- **One cell size per strip.** A multi-frame sheet is a single horizontal
  strip of N equal cells, every frame centred the same way in its cell. Do
  not let a tool crop each frame to its own bounding box — session P found
  that destroys the size progression that *is* the animation and makes the
  effect jitter against the car frame to frame.
- **Drop-in paths.** An icon replaces the file of the same name under
  `sprites/skills/`; nothing in the code changes. A new *sheet* is a new file
  and needs a few lines in the skill's own script to load and frame it — each
  section below says exactly what the script would want to be handed.
- **The choice icon sits on a coloured disc.** Self skills draw on green
  (`0.32, 0.82, 0.42`), opponent skills on red (`0.92, 0.28, 0.28`), with a
  white ring. A glyph whose dominant colour is that green or red vanishes
  into its own background — the placeholders lean on white, black, orange,
  blue and mint for this reason.

**Icon spec, all six:** 32x32 (or 64x64, same aspect), one frame, transparent,
the subject filling ~80% of the canvas, a 1px dark outline so it survives on
either disc. Drawn at ~28px on screen (`SKILL_ICON_RADIUS_FRAC` × lane width,
× 1.5 for the glyph), so a silhouette a player can name at that size matters
more than detail.

A prompt that has produced usable results for this style, adjust the subject:

> 32x32 pixel art icon, transparent background, PNG with alpha, hard pixel
> edges, no anti-aliasing, 1px dark outline, flat colours with a single
> highlight, retro arcade style, subject centred and filling the canvas:
> *[subject]*. No text, no border, no drop shadow.

---

## Make Way (`siren`, self) — `SirenSkill.gd`

**What the code draws today, all procedural:** a red/blue light bar on the
car's roof strobing out of phase (two lamps with beams thrown up the road), a
translucent corridor painted up the player's lane with chevrons racing along
it, and traffic being handed to the existing lane-change machine to pull
aside.

**Icon** — `sprites/skills/icon_siren.png`: a police beacon / roof light bar,
red and blue, throwing two short beams. Avoid a plain red dome (it disappears
on the red disc when the same icon is ever reused on the opponent side).

**Sheet 1, the light bar** — 6 cells, each 48x16, top-down, a rectangular
roof bar with a red lamp on the left and a blue lamp on the right: frames
alternate red-lit / both-dim / blue-lit / both-dim / red-lit / blue-lit, so a
6-frame loop at ~12fps strobes. `SirenSkill._draw_lamp()` is the thing this
replaces; it would be scaled to `car_size().x * 0.6` wide and positioned at
`player_car.position + (0, -car_h * 0.1)`.

**Sheet 2, optional, a corridor chevron** — 1 cell, 24x12, a single ">" arrow
pointing up (nose -y), white with a 1px outline, transparent. Used as a tile
along the lane instead of the drawn polyline.

---

## Pit Stop (`pitstop`, self) — `PitStopSkill.gd`

**Icon** — `sprites/skills/icon_pitstop.png`: a heart with a white repair
cross cut out of it (the placeholder), or a wrench crossed with a heart. Must
not read as the life pip itself — it is an *action*, not a readout.

**What the code draws today, all procedural:** the refilled pip plays the
loss gesture backwards (swollen and invisible → solid, in its slot) and lands
with a white flash and a green ring on the road; four spanner glints pop up
round the car in a fixed sequence; a green cross (or, in the full-lives case,
an amber lightning bolt over the boost bar with a sweep stripe) rises off the
car and dissolves.

**Sheet 1, the pip returning** — `sprites/skills/fx_pitstop_pip_return.png`,
6 cells of **36x36** (2× the pip, centred on the slot): (1) four faint sparks
at the corners, (2) sparks converging, (3) a green outline-only heart at 2×,
(4) heart at 1.5× filling in, (5) heart at 1× with a white starburst behind,
(6) a fading ring only. Keep the heart's body pixels saturated red so
`HeartPips.tinted()`'s per-player recolour applies if it is ever routed
through it; sparks and ring in green `#5CEB75` and white. Replaces the
procedural ring and lets the pop happen *in* the art instead of via modulate.

**Sheet 2, the crew** — `sprites/skills/fx_pitstop_crew.png`, 8 cells of
**64x96**, transparent, with a car-shaped hole in the middle (the real car
sprite draws under it): (1–2) two tiny pit-crew figures (~12x16, helmets in
the fleet's palette) pop up at the car's left-front and right-rear, (3–5) a
spanner-glint sequence — a four-point white star at 7→11→7px alternating
sides — plus a green cross (14x14, 1px outline, lit core) rising from the
roof, (6–7) crew duck away, cross at +26px and fading, (8) empty but for a
last spark. Whole-pixel steps for the cross's rise.

**Sheet 3, fuel** — `sprites/skills/fx_pitstop_fuel.png`, 4 cells of
**24x24**: an amber jerry-can / nozzle with a black outline — (1) closed, (2)
tipping, (3) pouring with a 3px amber drop, (4) a lightning-bolt flash
`#FFC238`. Used for the full-lives fallback in place of the procedural bolt;
also a candidate for a one-frame boost-bar end-cap flash at **9px** tall to
match `BOOST_BAR_HEIGHT`.

---

## Compact (`compact`, self) — `CompactSkill.gd`

**What the code draws today:** a mint ring collapsing from the full-size
body onto the shrunken one at the moment of the shrink, the same ring running
outward again in the last 0.34s as a warning, corner brackets on the road at
the car's *old* footprint so the slack is measured rather than asserted, and
a low glow hugging the small car. The car itself is the player's normal skin
scaled down — no new car art is needed, the scale is uniform.

**Icon** — `sprites/skills/icon_compact.png`: a small car between two arrows
pointing inward at it (the placeholder), or a car with "compression lines"
either side. Mint/cyan reads best on the green disc.

**Sheet, the squeeze** — 5 cells, each 64x64, transparent: a square ring
(the car's outline) drawn at 100%, 85%, 70%, 66% then 66% with a bright flash
— i.e. the implode. Played forward at the shrink and *backward* at the
grow-back, which is why it wants to be a ring and not a directional effect.
Mint `(0.42, 0.98, 0.76)` is the colour the code uses; matching it keeps the
HUD bar and the road brackets in the same family.

---

## Detour (`roadblock`, opponent) — `RoadblockSkill.gd`

**Icon** — `sprites/skills/icon_roadblock.png`: an orange/white striped
roadworks barrier on two legs (the placeholder). Orange on the red disc is
fine; avoid a red-dominant barrier.

**Sprite, the barrier itself** — `sprites/skills/barrier.png` is the drop-in
path (currently 48x20). Wanted: **96x40**, same ~2.4:1 aspect, a striped
Type-III barricade seen from above-and-slightly-front: a dark top rail, three
orange/white diagonal stripe bands, two legs with feet, a 1px outline. It is
spawned as an ordinary `Car`, so the collision box is 80% × 85% of the drawn
size — keep the legs inside the silhouette rather than splayed wide, or the
hit box will be much smaller than the art looks.

It is placed at `width_frac` 1.0 — a full lane, edge to edge — so the two
end legs will visually touch a neighbour's; draw it knowing that. Match the
fleet's soft-shaded render style and value range rather than hard-outlined
flat pixel art, or it reads as pasted on (exactly as the first taxi did, §5
session I).

**What the code draws today besides the barrier:** a 14px yellow/black hazard
band across the visible top edge of the victim's board, pulsing three times
over 0.9s when the skill lands and once, more quietly, per line.

**Sheet, warning lamp** — 2 cells of **16x16**, an amber dome off/on, to sit
on the barrier's top rail. Would go on as a child `Sprite2D` of the barrier
if a future version blinks it.

**Sheet, cones** — 3 cells of **40x40**, top-down traffic cones (plain,
striped, knocked over), to dress the pocket behind a line. Decoration only —
they would spawn without collision.

**Sheet, damage** — 3 cells of **96x40**: the barrier intact → cracked rail →
boards flying. Feeds `_play_destruction_effect()`'s `frames` parameter so a
barrier hit gets its own break instead of the car explosion it plays today.

**Strip, optional, the hazard band** — one tileable **360x14** yellow/black
chevron strip to replace the procedural band in `draw_overlay()`.

---

## Oil Slick (`slick`, opponent) — `SlickSkill.gd`

**What the code draws today:** nine irregular dark puddles on lane centres,
streaked 1.5x along the direction of travel, each with a smaller rainbow-sheen
patch whose hue crawls, a wet glint along the upper edge, scrolling down with
the board's own odometer; plus two tapered tyre smears behind the car that
kick sideways with the slide.

**Icon** — `sprites/skills/icon_slick.png`: a black puddle with a pale sheen
highlight and two falling drips (the placeholder). Keep the puddle near-black
with a blue-white highlight so it reads on red.

**Sheet 1, puddles** — 4 cells, each 64x96 (taller than wide — the streak is
along travel, i.e. vertical), transparent: four differently-shaped dark spills
with a soft rainbow film patch offset toward the top-left of each and a thin
light rim along the *top* edge. `SlickSkill._draw_spills()` would pick one per
puddle instead of generating a polygon, and scale it to `lane_width ×
[0.45..1.05]`.

**Sheet 2, optional, the sheen** — 1 cell, 32x32, a tileable rainbow-oil
texture, low contrast, to be additive-blended over the puddles.

---

## Smoke Screen (`smoke`, opponent) — `SmokeScreenSkill.gd`

**Icon** — `sprites/skills/icon_smoke.png`: a bank of grey smoke, lit from
inside (the placeholder). Light grey on the red disc is the most legible of
the six.

**What the code draws today, all procedural:** a five-slice gradient band
from just under the HUD strip to ~52% of the board, feathered at both ends,
plus 14 soft puffs (a faint halo and a lighter core each) scrolling down with
the road, swaying sideways and breathing, thinning to nothing at the band's
bottom feather. Warm light grey, `SMOKE = (0.74, 0.72, 0.70)`.

**Soft alpha edges are wanted for everything below** — the one exception to
the hard-edge rule. This is a volumetric effect; hard-edged puffs read as
cartoon clouds, and the fleet is soft-rendered so a crisp outlined cloud looks
"added afterwards". Base tone ≈ `#BDB8B3`, cores lifted toward `#D0CBC6`,
undersides cooled toward `#9A9AA0`; everything lighter than the asphalt.

**Sheet 1, a seamless smoke tile — replaces the base band.** One **256x256**
tile, seamless on **all four edges** (it scrolls vertically and is offset
sideways by the sway). Cloudy density variation in *alpha only* (0.3–0.7
across the tile, colour near-constant); no distinct blobs, no direction.
Drawn tiled under the same top/bottom feather the code uses now.

**Sheet 2, puffs — replaces the two circles per puff.** 6 cells of **96x96**
on one strip: one soft cloud per cell filling ~80% of it, centred, lit from
above (lighter top, cooler bottom), edges dissolving to alpha 0 by the cell
border so scaling needs no crop. Variants differ in silhouette, not tone.
They are over-drawn at 30–80% alpha, so no dithering.

**Sheet 3, optional, the roll-in front** — 6 frames of **360x96** on a
vertical strip: the leading edge of the bank seen from above, frame 1 thin
wisps, frame 6 a full billowing edge. **The front is the bottom edge of the
frame** (smoke rolls *down* the board toward the player); horizontally
seamless so it can be sway-offset. Played once over the 0.4s fade-in at the
band's advancing bottom edge.

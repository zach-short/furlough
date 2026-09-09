// The living hourglass, ported from Shared/UI/HourglassGeometry.swift and Hourglass.swift:
// the same 120 × 160 space, the same sand, drawn on a canvas. A level is a share of one
// charge by area, the top surface is a funnel, the pile is a cone at the angle of repose, and
// the stream is grains falling under gravity. Everything is a function of the phase, so a
// still phase draws a full stream.

export const C = {
  ground: '#0F0D0B', ember: '#E5563D', amber: '#F59E4A', cream: '#F5EFE6', muted: '#B8AFA3',
  faint: '#90877B', moss: '#7BC96F', pending: '#F2B544', sandLight: '#FFD59A',
} as const;

export type Glass = 'cream' | 'amber' | 'dim' | 'grey' | 'pending';
export type Tone = 'sand' | 'amber' | 'ember' | 'grey';
export type Pulse = 'none' | 'slow' | 'fast' | 'breathe';

export interface HourglassState {
  /** How full the top bulb is, 0…1. */
  sandLevel: number;
  /** How tall the pile is, 0…1. */
  moundLevel: number;
  isRunning: boolean;
  /** The stream stopped dead: the Anchor. */
  isFrozen: boolean;
  glass: Glass;
  sand: Tone;
  mound: Tone;
  glow: string | null;
  glowStrength: number;
  pulse: Pulse;
  /** A grain falls now and then: the window opens within ten minutes. */
  dropsGrain: boolean;
  showsAnchor: boolean;
}

const still: HourglassState = {
  sandLevel: 0, moundLevel: 0, isRunning: false, isFrozen: false, glass: 'cream', sand: 'sand',
  mound: 'sand', glow: null, glowStrength: 1, pulse: 'none', dropsGrain: false, showsAnchor: false,
};

export const States = {
  /** Inside a window: the top bulb holds what is left of it. `warned` is the 5-minute budget warning. */
  open: (level: number, warned = false): HourglassState => ({
    ...still, sandLevel: level, moundLevel: 1 - level, isRunning: true,
    glass: warned ? 'amber' : 'cream', mound: warned ? 'amber' : 'sand',
    glow: warned ? C.amber : C.moss, pulse: warned ? 'fast' : 'slow',
  }),
  /** Opens later today: every grain waits in the top. */
  comingSoon: (minutes: number): HourglassState => ({
    ...still, sandLevel: 1, glow: C.amber, glowStrength: 0.55, pulse: 'breathe', dropsGrain: minutes < 10,
  }),
  doneForToday: { ...still, moundLevel: 1, glow: C.amber, glowStrength: 0.35 } as HourglassState,
  usedUp: { ...still, moundLevel: 1, glass: 'dim', mound: 'ember', glow: C.ember, glowStrength: 0.45 } as HourglassState,
  alwaysBlocked: { ...still, moundLevel: 0.55, glass: 'grey', sand: 'grey', mound: 'grey' } as HourglassState,
  unconfigured: { ...still, glass: 'pending' } as HourglassState,
  anchored: {
    ...still, sandLevel: 0.55, moundLevel: 0.4, isFrozen: true, glow: C.ember, glowStrength: 0.9, showsAnchor: true,
  } as HourglassState,
};

/** Reads the states the pages name in markup: "open", "open:0.4", "open:0.4:warned", "comingSoon:4". */
export function stateNamed(name: string): HourglassState {
  const [kind, a, b] = name.split(':');
  switch (kind) {
    case 'open': return States.open(a ? Number(a) : 0.6, b === 'warned');
    case 'comingSoon': return States.comingSoon(a ? Number(a) : 60);
    case 'doneForToday': return States.doneForToday;
    case 'usedUp': return States.usedUp;
    case 'alwaysBlocked': return States.alwaysBlocked;
    case 'unconfigured': return States.unconfigured;
    case 'anchored': return States.anchored;
    default: return States.open(0.6);
  }
}

export function isAnimated(s: HourglassState): boolean {
  return s.isRunning || s.pulse !== 'none' || s.dropsGrain;
}

const PULSE: Record<Pulse, number> = { none: 0, slow: 3.4, fast: 1.2, breathe: 4.2 };

// MARK: Geometry

type Pt = [number, number];

const CX = 60;
const LID = 16;
const NECK_TOP = 76;
const NECK_BOTTOM = 84;
const FLOOR = 144;
const INSET = 1;
const TOP_SAND_BOTTOM = 81;
const STREAM_TOP = 80;
const ORIFICE = 1.5;
const FUNNEL_DEPTH = 0.36;
const FUNNEL_CURVE = 1.7;
const PILE_SLOPE = 0.62;
const PILE_TIP = 3.5;
const FULL_PEAK = 102;

function bezierX(y: number, p0: Pt, p1: Pt, p2: Pt, p3: Pt): number {
  const at = (t: number, a: number, b: number, c: number, d: number) => {
    const u = 1 - t;
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
  };
  let lo = 0, hi = 1;
  for (let i = 0; i < 28; i++) {
    const mid = (lo + hi) / 2;
    if (at(mid, p0[1], p1[1], p2[1], p3[1]) < y) lo = mid; else hi = mid;
  }
  const t = (lo + hi) / 2;
  return at(t, p0[0], p1[0], p2[0], p3[0]);
}

/** The right wall of the body path at `y`: straight sides, the two curves into the neck, and the neck. */
function rightWall(y: number): number {
  if (y < 32) return 98;
  if (y < NECK_TOP) return bezierX(y, [98, 32], [98, 52], [80, 64], [68, 76]);
  if (y <= NECK_BOTTOM) return 68;
  if (y < 128) return bezierX(y, [68, 84], [80, 96], [98, 108], [98, 128]);
  return 98;
}

const WALL_FROM = 12, WALL_TO = 148, WALL_STEP = 0.25;
const wall: number[] = [];
for (let y = WALL_FROM; y <= WALL_TO + 1e-9; y += WALL_STEP) wall.push(rightWall(y) - CX - INSET);

/** Half the inside width at `y`, inset from the wall. */
export function halfWidth(y: number): number {
  const pos = (Math.min(Math.max(y, WALL_FROM), WALL_TO) - WALL_FROM) / WALL_STEP;
  const i = Math.floor(pos);
  if (i >= wall.length - 1) return wall[wall.length - 1];
  return wall[i] + (wall[i + 1] - wall[i]) * (pos - i);
}

function topSandHalfWidth(y: number): number {
  if (y <= NECK_TOP) return halfWidth(y);
  const s = Math.min(1, (y - NECK_TOP) / (TOP_SAND_BOTTOM - NECK_TOP));
  return ORIFICE + (halfWidth(NECK_TOP) - ORIFICE) * Math.pow(1 - s, 1.6);
}

function funnelDepthFor(edge: number, half: number): number {
  return Math.min(FUNNEL_DEPTH * half, (TOP_SAND_BOTTOM - edge) * 0.8);
}

/** The top sand with its wall edge at `edge`: up the left side from the orifice, the funnel across, down the right. */
function topSand(edgeIn: number): Pt[] {
  const edge = Math.min(Math.max(edgeIn, LID), TOP_SAND_BOTTOM);
  if (edge >= TOP_SAND_BOTTOM - 0.05) return [];
  const half = topSandHalfWidth(edge);
  const depth = funnelDepthFor(edge, half);
  const step = 0.5;
  const pts: Pt[] = [[CX - ORIFICE, TOP_SAND_BOTTOM]];
  for (let y = TOP_SAND_BOTTOM - step; y > edge; y -= step) pts.push([CX - topSandHalfWidth(y), y]);
  const samples = 32;
  for (let k = 0; k <= samples; k++) {
    const u = (k / samples) * 2 - 1;
    const y = edge + depth * (1 - Math.pow(Math.abs(u), FUNNEL_CURVE));
    const side = topSandHalfWidth(y);
    pts.push([Math.min(Math.max(CX + u * half, CX - side), CX + side), y]);
  }
  for (let y = edge + step; y < TOP_SAND_BOTTOM; y += step) pts.push([CX + topSandHalfWidth(y), y]);
  pts.push([CX + ORIFICE, TOP_SAND_BOTTOM]);
  return pts;
}

function funnelBottom(edge: number): Pt {
  return [CX, edge + funnelDepthFor(edge, topSandHalfWidth(edge))];
}

/** The pile's surface at `x` for a tip at `peak`: a cone with a rounded tip, never below the floor. */
export function pileSurface(x: number, peak: number): number {
  const d = x - CX;
  return Math.min(FLOOR, peak + PILE_SLOPE * (Math.sqrt(d * d + PILE_TIP * PILE_TIP) - PILE_TIP));
}

/** The pile with its tip at `peak`: the cone where it clears the walls, the walls where it does not. */
function pile(peakIn: number): Pt[] {
  const peak = Math.min(Math.max(peakIn, NECK_BOTTOM), FLOOR);
  if (peak >= FLOOR - 0.05) return [];
  const wide = halfWidth(FLOOR);
  const right: Pt[] = [];
  const samples = 28;
  for (let k = 0; k <= samples; k++) {
    const x = CX + (wide * k) / samples;
    const y = pileSurface(x, peak);
    right.push([Math.min(x, CX + halfWidth(y)), y]);
  }
  const last = right[right.length - 1];
  if (last[1] < FLOOR) for (let y = last[1] + 1; y < FLOOR; y += 1) right.push([CX + halfWidth(y), y]);
  right.push([CX + wide, FLOOR]);
  const left = right.slice().reverse().map(([x, y]) => [2 * CX - x, y] as Pt);
  return left.concat(right.slice(1));
}

function area(poly: Pt[]): number {
  if (poly.length < 3) return 0;
  let s = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i], b = poly[(i + 1) % poly.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return Math.abs(s) / 2;
}

/** The parameter whose area is `a`, on a table whose areas fall as the parameter rises. */
function invert(table: Pt[], a: number): number {
  const first = table[0], last = table[table.length - 1];
  if (a >= first[1]) return first[0];
  if (a <= last[1]) return last[0];
  let lo = 0, hi = table.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (table[mid][1] > a) lo = mid; else hi = mid;
  }
  const [p0, a0] = table[lo], [p1, a1] = table[hi];
  if (a0 === a1) return p0;
  return p0 + ((p1 - p0) * (a0 - a)) / (a0 - a1);
}

const CHARGE = area(pile(FULL_PEAK));
const topTable: Pt[] = [];
for (let e = LID; e <= TOP_SAND_BOTTOM + 1e-9; e += 0.25) topTable.push([e, area(topSand(e))]);
const pileTable: Pt[] = [];
for (let p = NECK_BOTTOM; p <= FLOOR + 1e-9; p += 0.25) pileTable.push([p, area(pile(p))]);

function topEdge(level: number): number {
  return invert(topTable, Math.max(0, Math.min(1, level)) * CHARGE);
}
function peakFor(level: number): number {
  return invert(pileTable, Math.max(0, Math.min(1, level)) * CHARGE);
}

// MARK: The stream

interface Grain { x: number; y: number; r: number; stretch: number; alpha: number }

const RATE = 34;
const EXIT = 16;
const GRAVITY = 150;
const SPREAD = 1.0;
const WIDENING = 0.9;
const SPLASH_LIFE = 0.42;
const SPLASH_CHANCE = 0.4;
/** The frame the Anchor stops the stream on. */
const FROZEN_PHASE = 2.75;

/** A steady value in 0..<1 for a grain and a salt. */
function noise(i: number, salt: number): number {
  let h = (Math.imul(i | 0, 0x9e3779b1) ^ Math.imul(salt + 0x51, 0x85ebca77)) >>> 0;
  h = Math.imul(h ^ (h >>> 15), 0x2c1b3c6d) >>> 0;
  h = Math.imul(h ^ (h >>> 12), 0x297a2d39) >>> 0;
  h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
}

function fallTime(top: number, landing: number): number {
  const drop = Math.max(0, landing - top);
  return (-EXIT + Math.sqrt(EXIT * EXIT + 2 * GRAVITY * drop)) / GRAVITY;
}

/** Every grain in the air and every chip on the pile at `phase`. */
function grains(phase: number, top: number, landing: number, surface: (x: number) => number): Grain[] {
  const flight = fallTime(top, landing);
  const out: Grain[] = [];
  if (flight <= 0.01) return out;
  const first = Math.floor((phase - flight - SPLASH_LIFE) * RATE) - 1;
  const last = Math.floor(phase * RATE) + 1;
  for (let i = first; i <= last; i++) {
    const born = (i + 0.45 * (noise(i, 0) - 0.5)) / RATE;
    const t = phase - born;
    if (t < 0 || t >= flight + SPLASH_LIFE) continue;
    const side = noise(i, 1) * 2 - 1;
    const sway = 0.35 * Math.sin(born * 2.1) + 0.2 * Math.sin(born * 5.3);
    const r = 1.05 + 0.5 * noise(i, 2);
    if (t < flight) {
      const y = top + EXIT * t + 0.5 * GRAVITY * t * t;
      const x = CX + sway + side * (SPREAD + (WIDENING * t) / flight);
      const speed = EXIT + GRAVITY * t;
      out.push({ x, y, r, stretch: speed * 0.011, alpha: 0.8 + 0.2 * noise(i, 3) });
    } else if (noise(i, 4) < SPLASH_CHANCE) {
      const age = t - flight;
      const land = CX + sway + side * (SPREAD + WIDENING);
      for (let j = 0; j < 2; j++) {
        const sign = j === 0 ? -1 : 1;
        const vx = sign * (8 + 14 * noise(i, 5 + j));
        const vy = -(18 + 18 * noise(i, 7 + j));
        const x = land + vx * age;
        const y = Math.min(landing + vy * age + 0.5 * GRAVITY * age * age, surface(x) - 0.8);
        out.push({ x, y, r: 0.85 + 0.45 * noise(i, 9 + j), stretch: 0, alpha: 1 - age / SPLASH_LIFE });
      }
    }
  }
  return out;
}

/** A single grain that slips through now and then: falls, hops once, and is gone. */
function loneGrain(phase: number, top: number, landing: number, period = 3.2): Grain | null {
  const t = phase % period;
  const flight = fallTime(top, landing);
  if (t < flight) {
    const speed = EXIT + GRAVITY * t;
    return { x: CX, y: top + EXIT * t + 0.5 * GRAVITY * t * t, r: 1.6, stretch: speed * 0.008, alpha: 1 };
  }
  const hop = 24;
  const age = t - flight;
  const rest = (2 * hop) / GRAVITY;
  if (age >= rest + 0.35) return null;
  const y = age < rest ? landing - hop * age + 0.5 * GRAVITY * age * age : landing;
  const fade = age < rest ? 1 : 1 - (age - rest) / 0.35;
  return { x: CX + 3.5 * Math.min(age, rest), y, r: 1.6, stretch: 0, alpha: fade };
}

// MARK: Drawing

const rgbCache = new Map<string, [number, number, number]>();
function rgb(hex: string): [number, number, number] {
  let c = rgbCache.get(hex);
  if (!c) {
    const n = parseInt(hex.slice(1), 16);
    c = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    rgbCache.set(hex, c);
  }
  return c;
}
function rgba(hex: string, a: number): string {
  const [r, g, b] = rgb(hex);
  return `rgba(${r},${g},${b},${a})`;
}

const GLASS_FILL: Record<Glass, string> = {
  cream: 'rgba(255,255,255,.07)', amber: rgba(C.amber, 0.12), dim: 'rgba(255,255,255,.045)',
  grey: 'rgba(255,255,255,.035)', pending: rgba(C.pending, 0.03),
};
/** The 1 pt edge: bright top left, faint middle, bright bottom right. */
const GLASS_STROKE: Record<Glass, [string, number, number, number]> = {
  cream: ['#FFFFFF', 0.6, 0.14, 0.45], amber: [C.amber, 0.95, 0.35, 0.8], dim: ['#FFFFFF', 0.38, 0.1, 0.3],
  grey: ['#FFFFFF', 0.3, 0.1, 0.24], pending: [C.pending, 0.95, 0.55, 0.9],
};
const CAP_OPACITY: Record<Glass, number> = { cream: 0.92, amber: 0.92, dim: 0.55, grey: 0.55, pending: 0.35 };
/** Top to bottom over the whole glass, so the top sand is light and the mound is deep. */
const TONE_STOPS: Record<Tone, [string, number][]> = {
  sand: [[C.sandLight, 0], [C.amber, 0.55], [C.ember, 1]],
  amber: [[C.sandLight, 0], [C.amber, 0.6], [C.amber, 1]],
  ember: [[C.ember, 0], [C.ember, 0.5], ['#9C3524', 1]],
  grey: [['#8B847A', 0], ['#6A635B', 0.6], ['#4E4841', 1]],
};
/** Chips fade as they settle; a fill has one opacity, so they are drawn in a few bands. */
const LAYERS: [number, number, number][] = [[0.78, 1.01, 0.96], [0.52, 0.78, 0.68], [0.26, 0.52, 0.38], [-1, 0.26, 0.14]];

function bodyPath(ctx: CanvasRenderingContext2D) {
  ctx.beginPath();
  ctx.moveTo(22, 12); ctx.lineTo(98, 12); ctx.lineTo(98, 32);
  ctx.bezierCurveTo(98, 52, 80, 64, 68, 76); ctx.lineTo(68, 84);
  ctx.bezierCurveTo(80, 96, 98, 108, 98, 128); ctx.lineTo(98, 148); ctx.lineTo(22, 148); ctx.lineTo(22, 128);
  ctx.bezierCurveTo(22, 108, 40, 96, 52, 84); ctx.lineTo(52, 76);
  ctx.bezierCurveTo(40, 64, 22, 52, 22, 32); ctx.closePath();
}

function polyPath(ctx: CanvasRenderingContext2D, pts: Pt[]) {
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
  ctx.closePath();
}

function toneGradient(ctx: CanvasRenderingContext2D, tone: Tone): CanvasGradient {
  const g = ctx.createLinearGradient(0, 0, 0, 160);
  for (const [c, at] of TONE_STOPS[tone]) g.addColorStop(at, c);
  return g;
}

function grainPath(ctx: CanvasRenderingContext2D, g: Grain) {
  ctx.moveTo(g.x + g.r, g.y);
  ctx.ellipse(g.x, g.y, g.r, g.r + g.stretch / 2, 0, 0, 2 * Math.PI);
}

/** The Anchor's mark, standing on the base half in the pile. Ported from Shared/UI/AnchorMark.swift. */
function drawAnchor(ctx: CanvasRenderingContext2D) {
  // Drawn in an 80 × 100 space whose ink spans x 2…78 and y 1…87.5, fitted into (50, 130, 20, 25).
  const s = Math.min(20 / 76, 25 / 86.5);
  ctx.save();
  ctx.translate(60 - 40 * s, 142.5 - 44.25 * s);
  ctx.scale(s, s);
  const skeleton = () => {
    ctx.beginPath();
    ctx.ellipse(40, 15, 10.5, 10.5, 0, 0, 2 * Math.PI);
    ctx.moveTo(40, 26); ctx.lineTo(40, 82);
    ctx.moveTo(17, 38); ctx.lineTo(63, 38);
    ctx.moveTo(12, 58); ctx.bezierCurveTo(12, 74, 24, 84, 40, 84); ctx.bezierCurveTo(56, 84, 68, 74, 68, 58);
  };
  const flukes = () => {
    ctx.beginPath();
    ctx.moveTo(7, 41); ctx.lineTo(2, 59); ctx.lineTo(18, 68); ctx.closePath();
    ctx.moveTo(73, 41); ctx.lineTo(78, 59); ctx.lineTo(62, 68); ctx.closePath();
  };
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const edge = 1 / s;
  ctx.strokeStyle = rgba(C.cream, 0.7);
  skeleton(); ctx.lineWidth = 7 + edge; ctx.stroke();
  flukes(); ctx.lineWidth = edge; ctx.stroke();
  ctx.strokeStyle = C.ember;
  ctx.fillStyle = C.ember;
  skeleton(); ctx.lineWidth = 7; ctx.stroke();
  flukes(); ctx.fill();
  ctx.restore();
}

export interface DrawOptions {
  /** The canvas size in CSS pixels. The transform must already carry the device pixel ratio. */
  width: number;
  height: number;
  /** False under Reduce Motion: the stream is a solid column and nothing pulses. */
  motion?: boolean;
  /** Seconds since the glass appeared, for the one-time outline pulse of an empty glass. */
  appearSeconds?: number | null;
}

/** One frame. Under 40 px tall it switches to the bolder chip drawing for rows and the page indicator. */
export function drawHourglass(ctx: CanvasRenderingContext2D, state: HourglassState, phase: number, o: DrawOptions) {
  const W = o.width, H = o.height;
  const scale = Math.min(W / 120, H / 160);
  const mini = 160 * scale < 40;
  const motion = o.motion ?? true;
  ctx.save();
  ctx.clearRect(0, 0, W, H);
  ctx.translate((W - 120 * scale) / 2, (H - 160 * scale) / 2);
  ctx.scale(scale, scale);

  const peak = peakFor(state.moundLevel);
  const landing = peak - 0.5;
  const capH = mini ? 10 : 8;
  const streaming = state.isRunning || state.isFrozen;
  const grainy = streaming && !mini && motion;
  const streamPhase = state.isFrozen ? FROZEN_PHASE : phase;
  const pulse = motion && state.pulse !== 'none' ? (Math.sin((phase / PULSE[state.pulse]) * 2 * Math.PI) + 1) / 2 : 0.5;

  if (state.glow) {
    ctx.save();
    ctx.translate(60, 118);
    const s = 0.94 + 0.12 * pulse;
    ctx.scale(s, (s * 34) / 46);
    ctx.globalAlpha = 0.72 + 0.28 * pulse;
    const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 46);
    g.addColorStop(0, rgba(state.glow, 0.95 * state.glowStrength));
    g.addColorStop(1, rgba(state.glow, 0));
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(0, 0, 46, 0, 2 * Math.PI); ctx.fill();
    ctx.restore();
  }

  bodyPath(ctx);
  ctx.fillStyle = GLASS_FILL[state.glass];
  ctx.fill();

  if (state.sandLevel > 0.002) {
    const edge = topEdge(state.sandLevel);
    const pts = topSand(edge);
    if (pts.length) {
      polyPath(ctx, pts);
      ctx.fillStyle = toneGradient(ctx, state.sand);
      ctx.fill();
      // The funnel: a shadow in the bowl where the sand slides down to the neck.
      const [fx, fy] = funnelBottom(edge);
      const r = Math.max(1, halfWidth(edge) * 1.15);
      const sh = ctx.createRadialGradient(fx, fy, 0, fx, fy, r);
      sh.addColorStop(0, `rgba(0,0,0,${mini ? 0.2 : 0.34})`);
      sh.addColorStop(1, 'rgba(0,0,0,0)');
      polyPath(ctx, pts);
      ctx.fillStyle = sh;
      ctx.fill();
    }
  }

  if (streaming) {
    const tw = mini ? 6 : 3, bw = mini ? 5 : 2.2;
    const bottom = Math.max(STREAM_TOP + 1, landing + 0.5);
    ctx.beginPath();
    ctx.moveTo(60 - tw / 2, STREAM_TOP); ctx.lineTo(60 + tw / 2, STREAM_TOP);
    ctx.lineTo(60 + bw / 2, bottom); ctx.lineTo(60 - bw / 2, bottom); ctx.closePath();
    ctx.fillStyle = rgba(C.sandLight, grainy ? 0.26 : 0.95);
    ctx.fill();
    if (grainy) {
      const gs = grains(streamPhase, STREAM_TOP, landing, (x) => pileSurface(x, peak));
      for (const [lo, hi, op] of LAYERS) {
        ctx.beginPath();
        let any = false;
        for (const g of gs) if (g.alpha > lo && g.alpha <= hi) { grainPath(ctx, g); any = true; }
        if (any) { ctx.fillStyle = rgba(C.sandLight, op); ctx.fill(); }
      }
      // Dust where the stream lands.
      const flicker = 0.8 + 0.2 * Math.sin(streamPhase * 13.1) * Math.sin(streamPhase * 7.3);
      ctx.save();
      ctx.translate(60, landing + 0.5);
      ctx.scale(1, 8 / 18);
      const d = ctx.createRadialGradient(0, 0, 0, 0, 0, 9);
      d.addColorStop(0, rgba(C.sandLight, 0.42 * flicker));
      d.addColorStop(1, rgba(C.sandLight, 0));
      ctx.fillStyle = d;
      ctx.beginPath(); ctx.arc(0, 0, 9, 0, 2 * Math.PI); ctx.fill();
      ctx.restore();
    }
  }

  if (state.dropsGrain && motion && !state.isRunning) {
    const g = loneGrain(phase, STREAM_TOP, landing);
    if (g) {
      ctx.beginPath(); grainPath(ctx, g);
      ctx.fillStyle = rgba(C.sandLight, g.alpha);
      ctx.fill();
    }
  }

  if (state.moundLevel > 0.002) {
    const pts = pile(peak);
    if (pts.length) {
      polyPath(ctx, pts);
      ctx.fillStyle = toneGradient(ctx, state.mound);
      ctx.fill();
      // Fresh sand at the tip, where the stream lands, is lighter than the settled slopes.
      const fr = ctx.createRadialGradient(60, peak + 1.5, 0, 60, peak + 1.5, 11);
      fr.addColorStop(0, rgba(C.sandLight, mini ? 0.18 : 0.28));
      fr.addColorStop(1, rgba(C.sandLight, 0));
      polyPath(ctx, pts);
      ctx.fillStyle = fr;
      ctx.fill();
    }
  }

  const [sc, st, sm, sb] = GLASS_STROKE[state.glass];
  const sg = ctx.createLinearGradient(0, 0, 120, 160);
  sg.addColorStop(0, rgba(sc, st)); sg.addColorStop(0.5, rgba(sc, sm)); sg.addColorStop(1, rgba(sc, sb));
  ctx.save();
  const appear = o.appearSeconds;
  if (state.glass === 'pending' && motion && appear != null && appear < 0.72) ctx.globalAlpha = 0.35 + 0.65 * (appear / 0.72);
  bodyPath(ctx);
  ctx.strokeStyle = sg;
  ctx.lineWidth = mini ? 7 : 2.5;
  ctx.lineJoin = 'round';
  ctx.stroke();
  ctx.restore();

  ctx.fillStyle = rgba(C.cream, CAP_OPACITY[state.glass]);
  ctx.beginPath(); ctx.roundRect(18, 16 - capH, 84, capH, 4); ctx.fill();
  ctx.beginPath(); ctx.roundRect(18, 144, 84, capH, 4); ctx.fill();

  if (!mini) {
    ctx.beginPath();
    ctx.moveTo(31, 20); ctx.bezierCurveTo(31, 34, 37, 42, 45, 50);
    ctx.strokeStyle = 'rgba(255,255,255,.55)';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.stroke();
    if (state.showsAnchor) drawAnchor(ctx);
  }
  ctx.restore();
}

// MARK: Running one on a canvas

export const reduceMotion = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

/** Sizes the backing store to the element's CSS size at the device pixel ratio. Returns the CSS size. */
export function fitCanvas(canvas: HTMLCanvasElement): { w: number; h: number; ctx: CanvasRenderingContext2D } {
  const w = canvas.clientWidth || Number(canvas.getAttribute('width')) || 120;
  const h = canvas.clientHeight || Number(canvas.getAttribute('height')) || 160;
  const dpr = Math.min(window.devicePixelRatio || 1, 3);
  const bw = Math.max(1, Math.round(w * dpr)), bh = Math.max(1, Math.round(h * dpr));
  if (canvas.width !== bw || canvas.height !== bh) { canvas.width = bw; canvas.height = bh; }
  const ctx = canvas.getContext('2d')!;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { w, h, ctx };
}

/**
 * A glass that draws itself: the first frame lands at once, still states redraw only when
 * something changes, and moving ones run on a frame clock that pauses while the canvas is
 * off screen. `set` swaps the state at any time.
 */
export class LivingHourglass {
  state: HourglassState;
  private canvas: HTMLCanvasElement;
  private visible = true;
  private raf = 0;
  private motion: boolean;
  private appeared = performance.now();

  constructor(canvas: HTMLCanvasElement, state: HourglassState, opts: { still?: boolean } = {}) {
    this.canvas = canvas;
    this.state = state;
    this.motion = !reduceMotion() && !opts.still;
    this.draw(performance.now());
    if ('IntersectionObserver' in window) {
      new IntersectionObserver((entries) => {
        this.visible = entries.some((e) => e.isIntersecting);
        if (this.visible) this.schedule();
      }, { rootMargin: '80px' }).observe(canvas);
    }
    if ('ResizeObserver' in window) new ResizeObserver(() => this.draw(performance.now())).observe(canvas);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) this.schedule(); });
    this.schedule();
  }

  set(state: HourglassState) {
    this.state = state;
    if (this.running) this.schedule(); else this.draw(performance.now());
  }

  private get running() {
    return this.motion && isAnimated(this.state);
  }

  private draw(now: number) {
    const { w, h, ctx } = fitCanvas(this.canvas);
    drawHourglass(ctx, this.state, now / 1000, {
      width: w, height: h, motion: this.motion, appearSeconds: (now - this.appeared) / 1000,
    });
  }

  private schedule() {
    if (this.raf || !this.running || !this.visible) return;
    this.raf = requestAnimationFrame(this.frame);
  }

  private frame = (now: number) => {
    this.raf = 0;
    if (!this.visible) return;
    this.draw(now);
    this.schedule();
  };
}

/** Mounts every `<canvas data-hourglass="…">` on the page. */
export function mountHourglasses(root: ParentNode = document): LivingHourglass[] {
  return Array.from(root.querySelectorAll<HTMLCanvasElement>('canvas[data-hourglass]')).map((canvas) => {
    const glass = new LivingHourglass(canvas, stateNamed(canvas.dataset.hourglass || 'open'), { still: canvas.hasAttribute('data-still') });
    (canvas as HTMLCanvasElement & { hourglass?: LivingHourglass }).hourglass = glass;
    return glass;
  });
}

/** Linear blend of two states for the moments one gives way to another. Discrete fields switch at the midpoint. */
export function blendStates(a: HourglassState, b: HourglassState, t: number): HourglassState {
  const k = Math.max(0, Math.min(1, t));
  const mix = (x: number, y: number) => x + (y - x) * k;
  const late = k >= 0.5 ? b : a;
  let glow: string | null = late.glow;
  let strength = mix(a.glowStrength, b.glowStrength);
  if (a.glow && b.glow) {
    const [r1, g1, b1] = rgb(a.glow), [r2, g2, b2] = rgb(b.glow);
    glow = '#' + [mix(r1, r2), mix(g1, g2), mix(b1, b2)].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
  } else if (a.glow && !b.glow) { glow = a.glow; strength = a.glowStrength * (1 - k); }
  else if (!a.glow && b.glow) { glow = b.glow; strength = b.glowStrength * k; }
  return { ...late, sandLevel: mix(a.sandLevel, b.sandLevel), moundLevel: mix(a.moundLevel, b.moundLevel), glow, glowStrength: strength };
}

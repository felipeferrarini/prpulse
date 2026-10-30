// Renders the built-in mascots into Sources/PRPulse/Mascots/<id>/{sprites.png,mascot.json}.
// Usage: node scripts/make-mascots.mjs        (or: make mascots)
//
// Each mascot is a sprite sheet: one row per mood, one column per frame, 28 by 28 pixels per frame.
// Every animation loops cleanly in the frame count of its mood. The art is drawn in code below.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const FPS = 8;
const STATES = [['calm', 24], ['sleep', 24], ['alert', 24], ['joy', 12], ['worried', 24], ['think', 12], ['sad', 24]];

/* ---------- a tiny pixel toolkit ---------- */
const W = 28, H = 28;
const blank = () => Array.from({ length: H }, () => Array(W).fill(null));
const put = (g, x, y, c) => { x = Math.round(x); y = Math.round(y); if (x >= 0 && x < W && y >= 0 && y < H) g[y][x] = c; };
const rect = (g, x, y, w, h, c) => { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) put(g, x + i, y + j, c); };
const ell = (g, cx, cy, rx, ry, c) => {
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const dx = (x - cx) / rx, dy = (y - cy) / ry;
    if (dx * dx + dy * dy <= 1) g[y][x] = c;
  }
};
const poly = (g, pts, c) => {
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const px = x + .5, py = y + .5; let inside = false;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const [xi, yi] = pts[i], [xj, yj] = pts[j];
      if ((yi > py) !== (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) inside = !inside;
    }
    if (inside) g[y][x] = c;
  }
};
const outline = (g, c) => {
  const o = g.map(r => r.slice());
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (!g[y][x]) {
    if ((y > 0 && g[y - 1][x]) || (y < H - 1 && g[y + 1][x]) || (x > 0 && g[y][x - 1]) || (x < W - 1 && g[y][x + 1])) o[y][x] = c;
  }
  return o;
};
const recolor = (g, fn) => { for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (g[y][x]) g[y][x] = fn(x, y, g[y][x]) || g[y][x]; };
const bits = (g, x, y, rows, c, on = '#') => rows.forEach((r, j) => [...r].forEach((ch, i) => { if (ch === on) put(g, x + i, y + j, c); }));
const shift = (g, dy) => { const o = blank(); for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const ny = y + dy; if (g[y][x] && ny >= 0 && ny < H) o[ny][x] = g[y][x]; } return o; };

const DIGITS = {
  0: ['###', '#.#', '#.#', '#.#', '###'], 1: ['.#.', '##.', '.#.', '.#.', '###'], 2: ['###', '..#', '###', '#..', '###'],
  3: ['###', '..#', '###', '..#', '###'], 4: ['#.#', '#.#', '###', '..#', '..#'], 5: ['###', '#..', '###', '..#', '###'],
  6: ['###', '#..', '###', '#.#', '###'], 7: ['###', '..#', '..#', '.#.', '.#.'], 8: ['###', '#.#', '###', '#.#', '###'], 9: ['###', '#.#', '###', '..#', '###'],
};
const GLYPH = {
  check: ['....#', '...#.', '#.#..', '.#...'], bang: ['#', '#', '#', '.', '#'], dots: ['#.#.#'], q: ['##.', '..#', '.#.', '...', '.#.'], z: ['###', '.#.', '###'],
};

/* ---------- faces ---------- */
const EYES = {
  open:  { w: 2, px: [[0, -1, 'h'], [1, -1, '#'], [0, 0, '#'], [1, 0, '#'], [0, 1, '#'], [1, 1, '#']] },
  blink: { w: 2, px: [[0, 0, '#'], [1, 0, '#']] },
  wide:  { w: 3, px: [[0, -1, 'h'], [1, -1, '#'], [2, -1, '#'], [0, 0, '#'], [1, 0, '#'], [2, 0, '#'], [0, 1, '#'], [1, 1, '#'], [2, 1, '#']] },
  happy: { w: 3, px: [[1, -1, '#'], [0, 0, '#'], [2, 0, '#']] },
  sleep: { w: 3, px: [[0, 0, '#'], [1, 0, '#'], [2, 0, '#']] },
  up:    { w: 2, px: [[0, -2, '#'], [1, -2, 'h'], [0, -1, '#'], [1, -1, '#'], [0, 0, '#'], [1, 0, '#']] },
  sad:   { w: 2, px: [[0, -1, 'h'], [1, -1, '#'], [0, 0, '#'], [1, 0, '#'], [0, 1, '#'], [1, 1, 'tear']], extra: [[1, 2, 'tear']] },
};
const MOUTH = {
  smile: [[-2, 0], [-1, 1], [0, 1], [1, 1], [2, 0]],
  open:  [[-1, 0], [0, 0], [1, 0], [-1, 1], [0, 1, 'p'], [1, 1]],
  o:     [[-1, 0], [0, 0], [-1, 1], [0, 1]],
  wavy:  [[-2, 1], [-1, 0], [0, 1], [1, 0], [2, 1]],
  flat:  [[-1, 0], [0, 0], [1, 0]],
  frown: [[-2, 1], [-1, 0], [0, 0], [1, 0], [2, 1]],
};
const MOODS = {
  calm:    { eyes: 'open',  mouth: 'smile', label: 'Tudo em dia',          hint: 'ícone sem número' },
  sleep:   { eyes: 'sleep', mouth: 'o',     label: 'Dormindo',             hint: 'em dia há um tempão' },
  alert:   { eyes: 'wide',  mouth: 'o',     label: 'Precisa de você',      hint: 'ícone com número' },
  joy:     { eyes: 'happy', mouth: 'open',  label: 'Item novo',            hint: 'chegou algo, balão' },
  worried: { eyes: 'open',  mouth: 'wavy',  label: 'PR parada há dias',    hint: 'espera de 3 dias ou mais' },
  think:   { eyes: 'up',    mouth: 'flat',  label: 'Atualizando',          hint: 'consultando o GitHub' },
  sad:     { eyes: 'sad',   mouth: 'frown', label: 'Sem conexão',          hint: 'ícone vermelho' },
};

function face(g, spec, mood, f) {
  const m = MOODS[mood]; let eyes = m.eyes;
  if (mood === 'calm' && f % 24 === 20) eyes = 'blink';
  if (mood === 'alert' && f % 24 === 21) eyes = 'blink';
  if (mood === 'worried' && f % 24 === 21) eyes = 'blink';
  const e = EYES[eyes];
  const put1 = (x, y, k) => {
    const col = k === 'h' ? spec.hl : k === 'tear' ? '#7fd4ff' : spec.eye;
    put(g, x, y, col);
  };
  const lx = spec.cx - spec.eyeDx - Math.floor(e.w / 2), rx = spec.cx + spec.eyeDx - Math.floor((e.w - 1) / 2);
  const dx = mood === 'think' ? 1 : 0;
  [lx, rx].forEach(x0 => { e.px.forEach(([i, j, k]) => put1(x0 + i + dx, spec.eyeY + j, k)); (e.extra || []).forEach(([i, j, k]) => put1(x0 + i, spec.eyeY + j, k)); });
  if (mood === 'worried' && spec.brows) {
    [[lx, [[0, -3], [1, -2]]], [rx, [[1, -3], [0, -2]]]].forEach(([x0, pts]) => pts.forEach(([i, j]) => put(g, x0 + i, spec.eyeY + j, spec.eye)));
  }
  if (spec.cheek && mood !== 'sleep') { rect(g, spec.cx - spec.cheekDx - 1, spec.eyeY + 2, 2, 1, spec.cheek); rect(g, spec.cx + spec.cheekDx, spec.eyeY + 2, 2, 1, spec.cheek); }
  const mouth = MOUTH[m.mouth];
  mouth.forEach(([i, j, k]) => put(g, spec.cx + i, spec.mouthY + j, k === 'p' ? '#ff7a8a' : spec.mouth));
}

/* ---------- creatures ---------- */
function brasa(f, mood) {
  const B = '#ff9a3c', L = '#ffc070', D = '#e5701a', INK = '#3a1606', CREAM = '#ffe9c4';
  let g = blank();
  // tail with flame
  const t = [[18, 22], [19, 22], [20, 21], [21, 20], [21, 19], [22, 18]];
  t.forEach(([x, y]) => { put(g, x, y, B); put(g, x, y - 1, B); });
  const ry = [3.2, 3.9, 2.8, 3.5][f % 4] * (mood === 'sleep' ? .7 : 1), sx = [0, 1, 0, -1][f % 4] * .5;
  ell(g, 22.5 + sx, 14.2, 2.2, ry, '#ff4d2a'); ell(g, 22.5 + sx, 14.8, 1.5, ry * .72, '#ffb02e'); ell(g, 22.5 + sx, 15.4, .9, ry * .4, '#fff1a0');
  // body & feet
  ell(g, 13, 21, 5.5, 3.6, B); ell(g, 13, 21.8, 3.2, 2.4, CREAM);
  rect(g, 8, 24, 3, 2, CREAM); rect(g, 15, 24, 3, 2, CREAM);
  // head and ears
  const twitch = (mood === 'alert' && f % 6 < 2) ? -1 : 0;
  poly(g, [[4.5, 8], [5.5, 1.5 + twitch], [10.5, 6]], B); poly(g, [[21.5, 8], [20.5, 1.5 + twitch], [15.5, 6]], B);
  ell(g, 13, 12, 8.5, 7, B);
  poly(g, [[6, 6.5], [6.6, 3.6 + twitch], [8.8, 5.6]], '#ff8b86'); poly(g, [[20, 6.5], [19.4, 3.6 + twitch], [17.2, 5.6]], '#ff8b86');
  recolor(g, (x, y, c) => { if (c !== B || y > 18) return; if (y <= 7 && x <= 12) return L; if (y >= 17) return D; });
  g = outline(g, INK);
  face(g, { cx: 13, eyeY: 12, eyeDx: 4, mouthY: 15, eye: INK, hl: '#fff', cheek: '#ff7a7a', cheekDx: 7, mouth: INK, brows: true }, mood, f);
  return g;
}

function byte(f, mood) {
  const B = '#3fc8b8', L = '#8df0e3', D = '#1f8f86', INK = '#0d2b33', NAVY = '#16233d', CYAN = '#a8fff5';
  let g = blank();
  // tail stub with glowing tip
  rect(g, 19, 21, 3, 2, D);
  // feet, arms
  rect(g, 9, 24, 3, 2, D); rect(g, 15, 24, 3, 2, D);
  const wave = mood === 'joy' && f % 2 === 0;
  rect(g, 6, 18, 2, 3, B); if (mood === 'joy') rect(g, 20, wave ? 11 : 12, 2, 3, B); else rect(g, 20, 18, 2, 3, B);
  // body + head
  rect(g, 8, 16, 11, 8, B);
  rect(g, 5, 5, 17, 12, B);
  [[5, 5], [21, 5], [5, 16], [21, 16]].forEach(([x, y]) => g[y][x] = null);
  // crest
  poly(g, [[9, 5], [10.5, 1.5], [12, 5]], L); poly(g, [[12, 5], [13.5, .5], [15, 5]], L); poly(g, [[15, 5], [16.5, 1.5], [18, 5]], L);
  recolor(g, (x, y, c) => { if (c !== B) return; if (y <= 7) return L; if (y >= 20) return D; });
  const glow = ['#fff3a0', '#ffd75e', '#ffe98a', '#ffcb47'][f % 4];
  rect(g, 21, 21, 2, 2, glow);
  g = outline(g, INK);
  // visor
  rect(g, 7, 8, 13, 6, NAVY); [[7, 8], [19, 8], [7, 13], [19, 13]].forEach(([x, y]) => g[y][x] = B);
  // chin lights
  rect(g, 11, 19, 5, 1, L);
  face(g, { cx: 13, eyeY: 10, eyeDx: 3, mouthY: 12, eye: CYAN, hl: '#fff', cheek: null, cheekDx: 0, mouth: CYAN, brows: false }, mood, f);
  return g;
}


function gota(f, mood) {
  const B = '#4fa8ff', L = '#9dd3ff', D = '#2b6fd6', INK = '#0f2a55', BELLY = '#d6efff';
  let g = blank();
  rect(g, 9, 24, 3, 2, D); rect(g, 15, 24, 3, 2, D);
  const sway = [0, 1, 0, -1][f % 4] * .6;
  poly(g, [[5.5, 14], [1.5, 11 + (f % 2)], [2.5, 17]], B); poly(g, [[20.5, 14], [24.5, 11 + (f % 2)], [23.5, 17]], B);
  ell(g, 13, 16, 8.5, 7.5, B);
  poly(g, [[9.5, 11], [13 + sway, 1.5], [16.5, 11]], B);
  ell(g, 13, 19.5, 5, 3.5, BELLY);
  recolor(g, (x, y, c) => { if (c !== B) return; if (y <= 12 && x <= 12) return L; if (y >= 21 || x >= 20) return D; });
  g = outline(g, INK);
  put(g, 10, 9, '#fff'); put(g, 10, 10, '#fff');
  face(g, { cx: 13, eyeY: 15, eyeDx: 3, mouthY: 18, eye: INK, hl: '#fff', cheek: '#ff8fb0', cheekDx: 6, mouth: INK, brows: true }, mood, f);
  return g;
}

function broto(f, mood) {
  const B = '#6fd36f', L = '#b4f5a0', D = '#3e9f4b', INK = '#123b1d', BELLY = '#f4f0b8', LEAF = '#4cc25a', BROWN = '#8a5a2b';
  let g = blank();
  rect(g, 9, 24, 3, 2, BROWN); rect(g, 15, 24, 3, 2, BROWN);
  // arms
  rect(g, 4, 18, 3, 2, B); rect(g, 20, 18, 3, 2, B);
  ell(g, 13, 18, 8, 6.2, B);
  ell(g, 13, 20.5, 4.5, 3.2, BELLY);
  recolor(g, (x, y, c) => { if (c !== B) return; if (y <= 15 && x <= 12) return L; if (y >= 22 || x >= 20) return D; });
  // sprout: stem and leaves that sway or droop
  const lift = mood === 'alert' ? -1 : mood === 'sad' ? 2 : 0, w = [0, 1, 1, 0][f % 4];
  rect(g, 13, 8, 1, 6, D);
  poly(g, [[13, 10], [7 - w, 5 + lift], [6 - w, 9 + lift], [10, 11]], LEAF);
  poly(g, [[14, 10], [20 + w, 5 + lift], [21 + w, 9 + lift], [17, 11]], LEAF);
  g = outline(g, INK);
  if (mood === 'joy') { ell(g, 13.5, 5, 2.6, 2.6, '#ff8fb0'); put(g, 13, 5, '#ffe066'); put(g, 14, 5, '#ffe066'); put(g, 13, 6, '#ffe066'); }
  face(g, { cx: 13, eyeY: 17, eyeDx: 3, mouthY: 20, eye: INK, hl: '#fff', cheek: '#ff8fb0', cheekDx: 5, mouth: INK, brows: true }, mood, f);
  return g;
}

function nimbo(f, mood) {
  const B = '#b9a8ff', L = '#e0d8ff', D = '#8c78e0', INK = '#2b1d6b';
  let g = blank();
  ell(g, 13, 12, 8.5, 8, B); rect(g, 5, 12, 17, 8, B);
  // wavy hem
  [[7, 21], [13, 21.5], [19, 21]].forEach(([cx, cy], i) => ell(g, cx, cy + ((f + i) % 2 ? 0 : .6), 3, 2.6, B));
  // little hands
  rect(g, 3, 14, 3, 2, B); if (mood === 'joy') rect(g, 22, (f % 2) ? 8 : 9, 3, 2, B); else rect(g, 22, 14, 3, 2, B);
  // wisp on top
  put(g, 13, 3, B); put(g, 14, 2, B); put(g, 15, 2, B); put(g, 16, 3, B);
  recolor(g, (x, y, c) => { if (c !== B) return; if (y <= 9 && x <= 11) return L; if (y >= 19 || x >= 20) return D; });
  g = outline(g, INK);
  face(g, { cx: 13, eyeY: 11, eyeDx: 3, mouthY: 14, eye: INK, hl: '#fff', cheek: '#ff9fd0', cheekDx: 5, mouth: INK, brows: true }, mood, f);
  return g;
}

function seixo(f, mood) {
  const B = '#a7afc0', L = '#d4dae6', D = '#6f7890', INK = '#232838';
  let g = blank();
  rect(g, 8, 24, 4, 2, D); rect(g, 15, 24, 4, 2, D);
  rect(g, 3, 17, 3, 3, B); rect(g, 21, 17, 3, 3, B);
  ell(g, 13, 17, 9.5, 7.4, B);
  recolor(g, (x, y, c) => { if (c !== B) return; if (y <= 13 && x <= 12) return L; if (y >= 22 || x >= 21) return D; });
  // stone speckles and a crack
  [[7, 20], [19, 21], [18, 13], [8, 14]].forEach(([x, y]) => put(g, x, y, D));
  put(g, 15, 11, D); put(g, 16, 12, D); put(g, 16, 13, D);
  g = outline(g, INK);
  // glowing crystal on top
  const glow = ['#7ae6ff', '#b8f3ff', '#7ae6ff', '#58c8ff'][f % 4];
  poly(g, [[13, 1.5], [16.5, 6], [13, 10.5], [9.5, 6]], glow); poly(g, [[13, 3], [14.2, 6], [13, 8.5]], '#e6fbff');
  g = (() => { const o = outline(g.map(r => r.map(c => c === glow || c === '#e6fbff' ? c : (c === INK ? INK : c))), INK); return o; })();
  face(g, { cx: 13, eyeY: 16, eyeDx: 3, mouthY: 19, eye: INK, hl: '#fff', cheek: '#ff9a9a', cheekDx: 6, mouth: INK, brows: true }, mood, f);
  return g;
}

const CREATURES = {
  brasa: { name: 'Brasa', draw: brasa },
  byte:  { name: 'Byte',  draw: byte },
  gota:  { name: 'Gota',  draw: gota },
  broto: { name: 'Broto', draw: broto },
  nimbo: { name: 'Nimbo', draw: nimbo },
  seixo: { name: 'Seixo', draw: seixo },
};

/* ---------- effects (drawn over the creature) ---------- */
function effects(g, mood, f, count) {
  const Y = '#ffe066', R = '#ff5a4a', Bl = '#7fd4ff', Z = '#b8c4ff', Wh = '#ffffff';
  if (mood === 'alert' && f % 8 < 5) { const y = f % 8 < 2 ? 1 : 2; bits(g, 23, y, GLYPH.bang, R); }
  if (mood === 'sleep') { const k = Math.floor(f / 6) % 4; [[22, 8 - k * 2], [24, 4 - k]].slice(0, 1 + (k > 0)).forEach(([x, y], i) => bits(g, x, y < 0 ? 0 : y, GLYPH.z, Z)); }
  if (mood === 'joy') {
    [[3, 3], [24, 6], [2, 14], [25, 16]].forEach(([x, y], i) => { if ((f + i * 2) % 6 < 3) { put(g, x, y, Y); put(g, x - 1, y, Y); put(g, x + 1, y, Y); put(g, x, y - 1, Y); put(g, x, y + 1, Y); put(g, x, y, Wh); } });
  }
  if (mood === 'worried') { const y = 6 + (f % 8 < 4 ? 0 : 1); put(g, 4, y, Bl); put(g, 4, y + 1, Bl); put(g, 3, y + 1, Bl); put(g, 5, y + 1, Bl); put(g, 4, y + 2, Bl); }
  if (mood === 'think') { const n = 1 + Math.floor(f / 4) % 3; for (let i = 0; i < n; i++) rect(g, 20 + i * 3, 2, 2, 2, Wh); }
  if (mood === 'sad') bits(g, 22, 2, GLYPH.q, Bl);
}

function frame(key, mood, f, count) {
  let g = CREATURES[key].draw(f, mood, count);
  let oy = 0;
  if (mood === 'sleep') oy = [0, 0, 1, 1][Math.floor(f / 3) % 4];
  if (mood === 'alert') oy = [0, -1][f % 2];
  if (mood === 'joy') oy = -Math.round(5 * Math.abs(Math.sin((f % 12) / 12 * Math.PI)));
  if (mood === 'think') oy = [0, 0, 0, -1][f % 4];
  if (key === 'nimbo') oy += [-2, -3, -3, -2][Math.floor(f / 3) % 4];
  g = shift(g, oy);
  effects(g, mood, f, count);
  const shadow = blank();
  ell(shadow, 13, 26.5, (12 - (oy < 0 ? -oy : 0) * 1.1) / 2, 1, 'shadow');
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (!g[y][x] && shadow[y][x]) g[y][x] = 'shadow';
  return g;
}

// ---------- sheet and PNG ----------
const rgba = c => {
  if (c === 'shadow') return [0, 0, 0, 72];
  const v = parseInt(c.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255, 255];
};

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, 'ascii');
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

function png(width, height, pixels) {
  const stride = width * 4, raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) pixels.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

const columns = Math.max(...STATES.map(([, n]) => n));
for (const [id, creature] of Object.entries(CREATURES)) {
  const width = columns * W, height = STATES.length * H, pixels = Buffer.alloc(width * height * 4);
  const states = {};
  STATES.forEach(([mood, frames], row) => {
    states[mood] = { row, frames };
    for (let f = 0; f < frames; f++) {
      const g = frame(id, mood, f, 3);
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        if (!g[y][x]) continue;
        const o = ((row * H + y) * width + f * W + x) * 4;
        pixels.set(rgba(g[y][x]), o);
      }
    }
  });
  const dir = join(root, 'Sources/PRPulse/Mascots', id);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'sprites.png'), png(width, height, pixels));
  const manifest = { name: creature.name, author: 'PRPulse', frame: { width: W, height: H }, fps: FPS, states };
  writeFileSync(join(dir, 'mascot.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(`wrote ${id}: ${width}x${height}`);
}

// Clackey browser demo: plays the app's own sound files with the Web Audio API.
// Same behaviour as the Mac app: random sample variant (never twice in a row), one of five
// pitches (±3%), slight volume variation, and stereo panning by key / cursor position.
"use strict";

const REPO = "https://github.com/aakocval/clackey";
// Fixed asset name on every release, so this always downloads the newest DMG.
const DOWNLOAD = REPO + "/releases/latest/download/Clackey.dmg";
const PITCHES = [0.97, 0.985, 1, 1.015, 1.03];
const WIDE_KEYS = ["space", "back", "return"];

// MacBook (ANSI) layout: [event.code, legend, width, kind]
// kind: "mod" = word + symbol legend, "modR" = right-side modifier, "fn" = globe key
const LAYOUT = [
  [["Backquote", "`"], ["Digit1", "1"], ["Digit2", "2"], ["Digit3", "3"], ["Digit4", "4"], ["Digit5", "5"],
   ["Digit6", "6"], ["Digit7", "7"], ["Digit8", "8"], ["Digit9", "9"], ["Digit0", "0"], ["Minus", "-"],
   ["Equal", "="], ["Backspace", "delete", 1.5, "modR"]],
  [["Tab", "tab", 1.5, "mod"], ["KeyQ", "Q"], ["KeyW", "W"], ["KeyE", "E"], ["KeyR", "R"], ["KeyT", "T"],
   ["KeyY", "Y"], ["KeyU", "U"], ["KeyI", "I"], ["KeyO", "O"], ["KeyP", "P"], ["BracketLeft", "["],
   ["BracketRight", "]"], ["Backslash", "\\"]],
  [["CapsLock", "caps lock", 1.8, "mod"], ["KeyA", "A"], ["KeyS", "S"], ["KeyD", "D"], ["KeyF", "F"],
   ["KeyG", "G"], ["KeyH", "H"], ["KeyJ", "J"], ["KeyK", "K"], ["KeyL", "L"], ["Semicolon", ";"],
   ["Quote", "'"], ["Enter", "return", 1.7, "modR"]],
  [["ShiftLeft", "shift", 2.3, "mod", "⇧"], ["KeyZ", "Z"], ["KeyX", "X"], ["KeyC", "C"], ["KeyV", "V"],
   ["KeyB", "B"], ["KeyN", "N"], ["KeyM", "M"], ["Comma", ","], ["Period", "."], ["Slash", "/"],
   ["ShiftRight", "shift", 2.2, "modR", "⇧"]],
  [["Fn", "fn", 1, "fn"], ["ControlLeft", "control", 1, "mod", "⌃"], ["AltLeft", "option", 1, "mod", "⌥"],
   ["MetaLeft", "command", 1.25, "mod", "⌘"], ["Space", "", 5], ["MetaRight", "command", 1.25, "modR", "⌘"],
   ["AltRight", "option", 1, "modR", "⌥"], "ARROWS"],
];

const GLOBE_SVG = '<svg class="globe" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><circle cx="12" cy="12" r="10"/><ellipse cx="12" cy="12" rx="4.2" ry="10"/><path d="M2 12h20M4 7h16M4 17h16"/></svg>';

const $ = (id) => document.getElementById(id);
const settings = load();
let ctx = null;
let master = null;
let manifest = null;
const sets = {};          // folder -> { category: [AudioBuffer] }
const lastVariant = {};
const keyEls = new Map(); // code -> element
let typed = "";

// ---------------------------------------------------------------- settings

function load() {
  const s = { pack: null, volume: 0.8, mouse: true, spatial: true };
  try {
    // only accept known keys with the right types; anything else in storage is ignored
    const saved = JSON.parse(localStorage.getItem("clackey") || "{}");
    if (typeof saved.pack === "string") s.pack = saved.pack;
    if (Number.isFinite(saved.volume)) s.volume = Math.min(1, Math.max(0, saved.volume));
    if (typeof saved.mouse === "boolean") s.mouse = saved.mouse;
    if (typeof saved.spatial === "boolean") s.spatial = saved.spatial;
  } catch { /* storage blocked or corrupt: use defaults */ }
  return s;
}

const hasPack = (name) => Object.prototype.hasOwnProperty.call(manifest.packs, name)
  && Array.isArray(manifest.packs[name]);

function save() {
  try { localStorage.setItem("clackey", JSON.stringify(settings)); } catch { /* private mode */ }
}

// ---------------------------------------------------------------- audio

function category(file) {
  return file.toLowerCase().replace(/\.[a-z0-9]+$/, "").replace(/[-_].*$/, "");
}

async function loadSet(folder, files) {
  if (sets[folder]) return sets[folder];
  const set = {};
  await Promise.all(files.map(async (file) => {
    const url = "sounds/" + folder.split("/").map(encodeURIComponent).join("/") + "/" + encodeURIComponent(file);
    const data = await (await fetch(url)).arrayBuffer();
    const buffer = await new Promise((ok, fail) => ctx.decodeAudioData(data, ok, fail));
    (set[category(file)] ||= []).push(buffer);
  }));
  sets[folder] = set;
  return set;
}

function unlock() {
  if (ctx && ctx.state === "suspended") ctx.resume();
}

function play(set, cat, pan) {
  if (!ctx || !set) return;
  const list = set[cat] || (WIDE_KEYS.includes(cat) ? set.down : null);
  if (!list || !list.length) return;

  let i = Math.floor(Math.random() * list.length);
  if (list.length > 1 && i === lastVariant[cat]) i = (i + 1) % list.length;
  lastVariant[cat] = i;

  const src = ctx.createBufferSource();
  src.buffer = list[i];
  src.playbackRate.value = PITCHES[Math.floor(Math.random() * PITCHES.length)];
  const gain = ctx.createGain();
  gain.gain.value = 0.8 + Math.random() * 0.2;
  src.connect(gain);
  if (settings.spatial && ctx.createStereoPanner) {
    const panner = ctx.createStereoPanner();
    panner.pan.value = Math.max(-1, Math.min(1, pan * 0.6));
    gain.connect(panner).connect(master);
  } else {
    gain.connect(master);
  }
  src.start();
}

const keySet = () => sets["Packs/" + settings.pack];
const mouseSet = () => sets.Mouse;

function soundFor(code) {
  if (code === "Space") return "space";
  if (code === "Enter" || code === "NumpadEnter") return "return";
  if (code === "Backspace" || code === "Delete") return "back";
  return "down";
}

// ---------------------------------------------------------------- keyboard UI

function buildKeyboard() {
  const deck = $("keyboard");
  for (const row of LAYOUT) {
    const r = document.createElement("div");
    r.className = "row";
    for (const k of row) {
      if (k === "ARROWS") { r.append(buildArrows()); continue; }
      r.append(buildKey(...k));
    }
    deck.append(r);
  }
}

function buildKey(code, legend, width = 1, kind = "", symbol = "") {
  const el = document.createElement("button");
  el.type = "button";
  el.className = "key";
  el.dataset.code = code;
  el.style.setProperty("--w", width);
  el.setAttribute("aria-label", code === "Space" ? "space" : legend);
  el.tabIndex = -1;
  if (kind === "fn") {
    el.innerHTML = '<span class="sym">fn</span>' + GLOBE_SVG;
  } else if (kind === "mod" || kind === "modR") {
    el.classList.add("mod");
    if (kind === "modR") el.classList.add("right");
    el.innerHTML = '<span class="word"></span>' + (symbol ? '<span class="sym"></span>' : "");
    el.querySelector(".word").textContent = legend;
    if (symbol) el.querySelector(".sym").textContent = symbol;
  } else {
    el.innerHTML = '<span class="main"></span>';
    el.querySelector(".main").textContent = legend;
  }
  keyEls.set(code, el);
  return el;
}

function buildArrows() {
  const wrap = document.createElement("div");
  wrap.className = "arrows";
  const stack = document.createElement("div");
  stack.className = "stack";
  stack.append(buildKey("ArrowUp", "▲"), buildKey("ArrowDown", "▼"));
  wrap.append(buildKey("ArrowLeft", "◀"), stack, buildKey("ArrowRight", "▶"));
  return wrap;
}

function panOf(el) {
  const deck = $("keyboard").getBoundingClientRect();
  const r = el ? el.getBoundingClientRect() : deck;
  return ((r.left + r.width / 2 - deck.left) / deck.width) * 2 - 1;
}

function press(code, el = keyEls.get(code)) {
  unlock();
  if (el) el.classList.add("down");
  play(keySet(), soundFor(code), panOf(el));
  $("hint").classList.add("hidden");
}

function release(code, el = keyEls.get(code)) {
  if (el) el.classList.remove("down");
  play(keySet(), "up", panOf(el));
}

function updateTyped(e) {
  if (e.metaKey || e.ctrlKey) return;
  if (e.key === "Backspace") typed = typed.slice(0, -1);
  else if (e.key === "Enter") typed = "";
  else if (e.key.length === 1) typed = (typed + e.key).slice(-80);
  else return;
  // show only the tail so the newest characters stay visible on small screens
  const max = Math.max(12, Math.floor(window.innerWidth / 22));
  $("typed-text").textContent = typed.slice(-max);
}

// ---------------------------------------------------------------- events

function wireEvents() {
  document.addEventListener("keydown", (e) => {
    if (e.target.closest && e.target.closest("input, button:not(.key)") && e.code === "Space") return;
    // keep the page from scrolling / quick-finding, but leave ⌘/⌃ shortcuts alone
    if (!e.metaKey && !e.ctrlKey && /^(Space|Tab|Quote|Slash|Arrow|Backspace)/.test(e.code)) e.preventDefault();
    if (e.repeat) return;
    press(e.code);
    updateTyped(e);
  });
  document.addEventListener("keyup", (e) => {
    release(e.code);
    // macOS doesn't send keyup for keys released while ⌘ is held
    if (e.key === "Meta") keyEls.forEach((el) => el.classList.remove("down"));
  });
  window.addEventListener("blur", () => keyEls.forEach((el) => el.classList.remove("down")));

  // Tap / click the on-screen keys (works on phones and tablets too).
  $("keyboard").addEventListener("pointerdown", (e) => {
    const el = e.target.closest(".key");
    if (!el) return;
    e.preventDefault();
    el.setPointerCapture(e.pointerId);
    press(el.dataset.code, el);
    const up = () => { release(el.dataset.code, el); el.removeEventListener("pointerup", up); el.removeEventListener("pointercancel", up); };
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
  });

  // Mouse / trackpad clicks anywhere else on the page.
  const clickPan = (e) => (e.clientX / window.innerWidth) * 2 - 1;
  document.addEventListener("pointerdown", (e) => {
    unlock();
    if (e.pointerType !== "mouse" || !settings.mouse || e.target.closest(".key")) return;
    play(mouseSet(), "mousedown", clickPan(e));
  });
  document.addEventListener("pointerup", (e) => {
    if (e.pointerType !== "mouse" || !settings.mouse || e.target.closest(".key")) return;
    play(mouseSet(), "mouseup", clickPan(e));
  });
}

function wireControls() {
  const packs = $("packs");
  for (const name of Object.keys(manifest.packs)) {
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("role", "radio");
    b.textContent = name;
    b.addEventListener("click", async () => {
      settings.pack = name;
      save();
      renderPacks();
      await loadSet("Packs/" + name, manifest.packs[name]);
      play(keySet(), "down", 0);   // preview
    });
    packs.append(b);
  }
  renderPacks();

  const volume = $("volume");
  volume.value = settings.volume;
  volume.addEventListener("input", () => {
    settings.volume = Math.min(1, Math.max(0, Number(volume.value) || 0));
    master.gain.value = settings.volume;
    save();
  });
  for (const id of ["mouse", "spatial"]) {
    const box = $(id);
    box.checked = settings[id];
    box.addEventListener("change", () => { settings[id] = box.checked; save(); });
  }
  $("download").href = DOWNLOAD;
  $("github").href = REPO;
}

function renderPacks() {
  for (const b of $("packs").children) b.setAttribute("aria-checked", String(b.textContent === settings.pack));
}

// ---------------------------------------------------------------- start

async function start() {
  buildKeyboard();
  if (matchMedia("(hover: none)").matches) $("hint").textContent = "Tap the keys to hear it.";

  const AudioCtx = window.AudioContext || window.webkitAudioContext;
  ctx = new AudioCtx({ latencyHint: "interactive" });
  master = ctx.createGain();
  master.gain.value = settings.volume;
  master.connect(ctx.destination);

  manifest = await (await fetch("sounds/manifest.json")).json();
  if (!hasPack(settings.pack)) settings.pack = manifest.default;
  wireControls();
  wireEvents();
  await loadSet("Packs/" + settings.pack, manifest.packs[settings.pack]);
  if (manifest.mouse.length) await loadSet("Mouse", manifest.mouse);
  // warm the other packs in the background so switching is instant
  for (const [name, files] of Object.entries(manifest.packs)) loadSet("Packs/" + name, files);
}

start().catch((err) => {
  console.error(err);
  $("hint").textContent = "Couldn't load sounds. Try reloading the page.";
});

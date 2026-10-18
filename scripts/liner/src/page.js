// Runs inside Liner's renderer, in an isolated world created by liner-bridge
// (it shares the DOM, localStorage and IndexedDB with Liner but none of its JS).
// Reads the lyrics Liner already downloaded for the current song and converts
// them to the Serpantinum/Astrax bridge format:
//   [{ time, text, words: [{ time, endTime, text }], bg?: [{ time, endTime, text, words }] }]
// Times are in seconds. Parsing uses @braccato/parsers (MIT), the same library
// Liner uses, so the timing is the same one Liner shows.
import { detectParser } from "@braccato/parsers";

const SESSION_KEY = "liner_lyrics_session_v1";
const ITEM_PREFIX = "liner_lyrics_v2_item_";
const DB_NAME = "liner_db_v1";

function lyricsSession() {
  try {
    const s = JSON.parse(localStorage.getItem(SESSION_KEY) || "{}").state || {};
    return { id: s.currentLyricsTrackId || null, offsets: s.trackOffsets || {} };
  } catch (e) {
    return { id: null, offsets: {} };
  }
}

function snapshot() {
  const md = navigator.mediaSession && navigator.mediaSession.metadata;
  const audio = document.querySelector("audio");
  const ses = lyricsSession();
  return {
    title: md ? String(md.title || "") : "",
    artist: md ? String(md.artist || "") : "",
    pos: audio ? audio.currentTime : -1,
    dur: audio && isFinite(audio.duration) ? audio.duration : 0,
    paused: audio ? audio.paused : true,
    lyricsId: ses.id,
    offsetMs: ses.id ? Number(ses.offsets[ses.id] || 0) : 0,
    stamp: Date.now() / 1000,
  };
}

function fromIndexedDb(id) {
  return new Promise((resolve) => {
    let req;
    try { req = indexedDB.open(DB_NAME); } catch (e) { resolve(null); return; }
    req.onerror = () => resolve(null);
    req.onsuccess = () => {
      const db = req.result;
      try {
        if (!db.objectStoreNames.contains("lyrics")) { db.close(); resolve(null); return; }
        const get = db.transaction("lyrics", "readonly").objectStore("lyrics").get(id);
        get.onsuccess = () => { db.close(); resolve(get.result || null); };
        get.onerror = () => { db.close(); resolve(null); };
      } catch (e) { db.close(); resolve(null); }
    };
  });
}

async function cachedItem(id) {
  try {
    const raw = localStorage.getItem(ITEM_PREFIX + id);
    if (raw) {
      const item = JSON.parse(raw);
      if (item && item.candidate) return item;
    }
  } catch (e) {}
  return fromIndexedDb(id);
}

// ---- raw formats -> braccato-style lines {startTimeMs, durationMs, words, parts} ----

// Musixmatch richsync: [{ ts, te, l: [{ c, o }] }], o = offset from ts (s)
function parseRichsync(arr) {
  return arr.map((line) => {
    const start = Math.round(line.ts * 1000);
    const end = Math.round(line.te * 1000);
    const toks = [];
    for (const w of Array.isArray(line.l) ? line.l : []) {
      if (!w || typeof w.c !== "string") continue;
      if (w.c.trim() === "") { if (toks.length) toks[toks.length - 1].c += w.c; }
      else toks.push({ c: w.c, o: w.o || 0 });
    }
    const at = (o) => { const ms = Math.round(o * 1000); return ms >= start ? ms : start + ms; };
    const parts = toks.map((t, i) => {
      const s = at(t.o);
      const e = i + 1 < toks.length ? at(toks[i + 1].o) : end;
      return { startTimeMs: s, durationMs: Math.max(0, e - s), words: t.c };
    });
    return { startTimeMs: start, durationMs: Math.max(0, end - start), words: toks.map((t) => t.c).join(""), parts };
  });
}

// Musixmatch subtitles: [{ text, time: { total } }] (line timing only)
function parseMxmSubtitles(arr) {
  return arr
    .filter((l) => typeof l.text === "string" && l.text.trim() !== "")
    .map((l) => ({ startTimeMs: Math.round(Number(l.time.total || 0) * 1000), durationMs: 0, words: l.text.trim() }));
}

function parseRaw(raw, durMs) {
  const t = raw.trim();
  if (t.startsWith("[")) {
    try {
      const arr = JSON.parse(t);
      if (Array.isArray(arr) && arr.length) {
        if (typeof arr[0].ts === "number") return parseRichsync(arr);
        if (arr[0].time && typeof arr[0].time.total === "number") return parseMxmSubtitles(arr);
      }
    } catch (e) {}
  }
  return detectParser(t).parse(t, durMs || undefined) || [];
}

// ---- braccato lines -> bridge lines ----

// parts are syllables; a word ends where a part ends in whitespace
function partsToWords(parts, offS) {
  const words = [];
  let open = false;
  for (const p of parts) {
    const text = String(p.words || "");
    const a = p.startTimeMs / 1000 + offS;
    const b = (p.startTimeMs + (p.durationMs || 0)) / 1000 + offS;
    const syl = { time: a, endTime: Math.max(a, b), text: text.trim() };
    if (open && words.length) {
      const w = words[words.length - 1];
      w.text += text;
      w.endTime = Math.max(w.endTime, b);
      if (syl.text !== "") w.syl.push(syl);
    } else if (text.trim() !== "") {
      words.push({ time: a, endTime: Math.max(a, b), text, syl: [syl] });
    } else {
      continue;
    }
    open = !/\s$/.test(text);
  }
  for (const w of words) {
    w.text = w.text.trim();
    // syllables only matter when a word has more than one ("Cu", "an", "do")
    if (w.syl.length < 2) delete w.syl;
  }
  return words.filter((w) => w.text !== "");
}

function toBridge(lines, offsetMs) {
  const offS = (offsetMs || 0) / 1000;
  const out = [];
  for (const ln of lines) {
    const time = Math.max(0, ln.startTimeMs / 1000 + offS);
    const parts = Array.isArray(ln.parts) ? ln.parts : [];
    const lead = parts.filter((p) => !p.isBackground);
    const back = parts.filter((p) => p.isBackground);
    const words = partsToWords(lead, offS);
    let text = words.length ? words.map((w) => w.text).join(" ") : String(ln.words || "").trim();
    if (text === "" && back.length === 0) continue;
    const line = { time, text, words };
    const bw = partsToWords(back, offS);
    if (bw.length) {
      // spicy-bridge sends background vocals without their ( ); Lyrics.qml adds them
      bw[0].text = bw[0].text.replace(/^\(/, "");
      bw[bw.length - 1].text = bw[bw.length - 1].text.replace(/\)$/, "");
      const kept = bw.filter((w) => w.text !== "");
      line.bg = [{ time: bw[0].time, endTime: bw[bw.length - 1].endTime,
                   text: kept.map((w) => w.text).join(" "), words: kept }];
      if (text === "") { line.text = "(" + line.bg[0].text + ")"; line.words = []; }
    }
    out.push(line);
  }
  out.sort((a, b) => a.time - b.time);
  // some formats give the last word of a line no end (it runs to the song end):
  // stop it shortly after the next line starts
  for (let i = 0; i + 1 < out.length; i++) {
    const cap = out[i + 1].time + 0.5;
    for (const w of out[i].words) w.endTime = Math.min(w.endTime, Math.max(w.time + 0.2, cap));
  }
  return out;
}

const norm = (t) => String(t || "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");

// Do two parsed lyrics follow the same timing? Lines are matched in order by text;
// they agree when most lines match and start within a quarter second of each other.
function timingAgrees(a, b) {
  const diffs = [];
  let j = 0;
  for (const la of a) {
    const ta = norm(la.words);
    if (!ta) continue;
    for (let k = j; k < Math.min(b.length, j + 4); k++) {
      if (norm(b[k].words) === ta) {
        diffs.push(Math.abs(la.startTimeMs - b[k].startTimeMs));
        j = k + 1;
        break;
      }
    }
  }
  const lines = a.filter((l) => norm(l.words)).length;
  if (!lines || diffs.length < lines * 0.6) return false;
  diffs.sort((x, y) => x - y);
  return diffs[Math.floor(diffs.length / 2)] <= 250;
}

async function lyrics(id, durS) {
  const item = await cachedItem(id);
  if (!item) return null;
  const all = [item.candidate, ...Object.values(item.providers || {}),
               ...(item.availableProviders || []).map((o) => o && o.candidate)]
    .filter((x) => x && x.lyrics && x.lyrics.content);
  if (!all.length) return null;
  const durMs = Math.round((durS || 0) * 1000);
  const parse = (c) => { try { return parseRaw(c.lyrics.content, durMs); } catch (e) { return []; } };
  // Liner's own pick (what its lyrics view shows) is the timing reference. A
  // syllable-level provider replaces it only when its timing matches, so the
  // bar gets syllables without drifting away from what Liner shows.
  let c = all[0];
  let lines = parse(c);
  let why = "liner";
  if (c.syncLevel !== "syllable_level") {
    const syl = all.find((x) => x.syncLevel === "syllable_level");
    if (syl) {
      const sl = parse(syl);
      if (sl.length && (!lines.length || timingAgrees(lines, sl))) { c = syl; lines = sl; why = "syllables"; }
      else why = "liner (syllable timing differs)";
    }
  }
  const ses = lyricsSession();
  const offsetMs = Number(ses.offsets[id] || 0);
  const mt = c.matchedTrack || {};
  return {
    provider: c.provider || "",
    syncLevel: c.syncLevel || "",
    choice: why,
    matchedTitle: mt.title || "",
    providers: [...new Set(all.map((x) => x.provider + ":" + x.syncLevel))],
    lyrics: toBridge(lines, offsetMs),
  };
}

// ---- reporter: like glass-lyrics inside Spotify, push state to liner-bridge ----
// Started once per page by liner-bridge, which then detaches DevTools (an attached
// session hides the song from MPRIS). Runs in the bridge's isolated world.
function startReporter(port) {
  if (globalThis.__astraxLinerReporter) return "running";
  const base = "http://127.0.0.1:" + port;
  const post = (path, obj) => {
    // text/plain + no-cors = a simple request: no preflight, nothing to answer
    try { fetch(base + path, { method: "POST", mode: "no-cors", body: JSON.stringify(obj) }).catch(() => {}); }
    catch (e) {}
  };
  const keyNow = () => {
    const md = navigator.mediaSession && navigator.mediaSession.metadata;
    return md && md.title ? String(md.artist || "").trim() + " - " + String(md.title).trim() : "";
  };
  // cover as the page has it: Chromium's own download of it to MPRIS sometimes fails
  const artNow = () => {
    const md = navigator.mediaSession && navigator.mediaSession.metadata;
    const list = md && md.artwork ? Array.from(md.artwork) : [];
    const px = (a) => parseInt(String(a.sizes || "0").split("x")[0], 10) || 0;
    list.sort((a, b) => px(b) - px(a));
    return list.length ? String(list[0].src || "") : "";
  };
  // Chromium sometimes publishes a song to MPRIS without its title/artist/cover. The
  // bridge sees that from outside and answers {poke:true}: set the SAME metadata again,
  // which makes Chromium send it afresh (Liner's own state is not touched).
  let lastPoke = 0;
  const repoke = () => {
    const md = navigator.mediaSession && navigator.mediaSession.metadata;
    if (!md || Date.now() - lastPoke < 4000) return;
    lastPoke = Date.now();
    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: md.title, artist: md.artist, album: md.album,
        artwork: Array.from(md.artwork).map((a) => ({ src: a.src, sizes: a.sizes, type: a.type })),
      });
    } catch (e) {}
  };
  // full state for the bridge's MPRIS mirror (see mirror.py); sent every 2 s and
  // at once when the song or its cover changes
  const hello = () => {
    const md = navigator.mediaSession && navigator.mediaSession.metadata;
    const a = document.querySelector("audio");
    const state = {
      key: keyNow(), art: artNow(), stamp: Date.now() / 1000,
      title: md ? String(md.title || "") : "", artist: md ? String(md.artist || "") : "",
      album: md ? String(md.album || "") : "",
      dur: a && isFinite(a.duration) ? a.duration : 0,
      pos: a ? a.currentTime : -1, paused: a ? a.paused : true, rate: a ? a.playbackRate : 1,
    };
    try {
      fetch(base + "/hello", { method: "POST", body: JSON.stringify(state) })
        .then((r) => r.json()).then((j) => { if (j && j.poke) repoke(); }).catch(() => {});
    } catch (e) {}
  };
  let lastSig = "";
  const watchChange = () => {
    const sig = keyNow() + "|" + artNow();
    if (sig !== lastSig) { lastSig = sig; hello(); }
  };
  let audio = null;
  const progress = () => {
    const key = keyNow();
    if (!audio || !key) return;
    post("/progress", { key, player: "liner", progress: audio.currentTime,
                        playing: !audio.paused, rate: audio.playbackRate, stamp: Date.now() / 1000 });
  };
  const hook = () => {
    const a = document.querySelector("audio");
    if (a === audio) return;
    audio = a;
    if (!a) return;
    for (const ev of ["timeupdate", "seeked", "play", "pause", "ratechange", "loadedmetadata"])
      a.addEventListener(ev, progress);
  };

  // lyrics: look again while Liner may still be fetching or upgrading them
  let job = null;      // { key, start, prevId, sig }
  let lastId = null;
  const lyricsTick = async () => {
    hook();
    const key = keyNow();
    if (!key) return;
    const now = Date.now() / 1000;
    if (!job || job.key !== key) job = { key, start: now, prevId: lastId, sig: null };
    if (now - job.start > 25 && job.sig) return;
    const ses = lyricsSession();
    if (!ses.id) return;
    if (ses.id === job.prevId && !job.sig && now - job.start < 8) return;
    const res = await lyrics(ses.id, audio && isFinite(audio.duration) ? audio.duration : 0);
    if (!res || !res.lyrics.length || keyNow() !== key) return;
    const sig = [ses.id, ses.offsets[ses.id] || 0, res.provider, res.lyrics.length].join("|");
    if (sig === job.sig) return;
    job.sig = sig;
    lastId = ses.id;
    post("/lyrics", Object.assign({ key, player: "liner", stamp: now }, res));
  };

  globalThis.__astraxLinerReporter = {
    hb: setInterval(hello, 2000),
    wc: setInterval(watchChange, 400),
    ly: setInterval(() => { lyricsTick().catch(() => {}); }, 1000),
    pr: setInterval(() => { hook(); if (audio && !audio.paused) progress(); }, 1000),
  };
  hook();
  progress();
  return "started";
}

globalThis.__astraxLiner = { snapshot, lyrics, parseRaw, toBridge, startReporter };

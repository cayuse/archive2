// Drives the browser jukebox player in headless Chrome on staging across real song changes and
// measures the silence between songs. Run through browser_player_e2e.sh (it sets everything up).
//
// What it checks: the next song is taken from the archive only in the last PREFETCH seconds, is
// shown as "up next", starts from the preload (not fetched at the end), the gap between songs,
// a skip mid-song, and a skip right after a prefetch (the prefetched song is used, not a new one).
// What it cannot check: iOS. Chrome on Linux has no lock screen and no iOS audio-session rules.
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const BASE = process.env.BASE || "http://127.0.0.1:3909";
const { JUKEBOX, EMAIL, PASSWORD } = process.env;
const PORT = 9333;
let failed = 0;
const check = (label, ok, extra = "") => { console.log(`  ${ok ? "ok  " : "FAIL"} ${label} ${extra}`); if (!ok) failed++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn("google-chrome", ["--headless=new", `--remote-debugging-port=${PORT}`, "--autoplay-policy=no-user-gesture-required",
  "--mute-audio", "--no-first-run", `--user-data-dir=${mkdtempSync(join(tmpdir(), "ajb-e2e-"))}`, "about:blank"], { stdio: "ignore" });
process.on("exit", () => chrome.kill());

let targets;
for (let i = 0; i < 40 && !targets; i++) { await sleep(250); targets = await fetch(`http://127.0.0.1:${PORT}/json`).then((r) => r.json()).catch(() => null); }
const ws = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r));
let seq = 0; const waiting = new Map(); const requests = [];
ws.addEventListener("message", (m) => {
  const d = JSON.parse(m.data);
  if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id); }
  if (d.method === "Network.requestWillBeSent") requests.push({ t: Date.now(), url: d.params.request.url });
});
const send = (method, params = {}) => new Promise((r) => { const id = ++seq; waiting.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
const js = async (expr) => (await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true })).result?.result?.value;
const go = async (url) => { await send("Page.navigate", { url }); await sleep(2500); };
await send("Network.enable"); await send("Page.enable");

await go(`${BASE}/login`);
await js(`(() => { const f = document.querySelector('form'); f.querySelector('[name=email]').value = ${JSON.stringify(EMAIL)};
  f.querySelector('[name=password]').value = ${JSON.stringify(PASSWORD)}; f.submit(); })()`);
await sleep(2500);
await go(`${BASE}/jukeboxes/${JUKEBOX}/player`);
check("player page has its controller", await js("!!window.ajbPlayer"));
const build = await js("window.AJB_BUILD");
check("the page reports its player build", /^[0-9a-f]{10}$/.test(build || ""), build);
check("one audio element, no Howler", (await js("typeof Howl")) === "undefined" && (await js("document.querySelectorAll('audio').length")) === 1);

// record the engine's end / play moments
await js(`(() => { const p = window.ajbPlayer, e = p.audioEngine; window.ev = [];
  const onEnd = e.onEnd, onPlay = e.onPlay;
  e.onEnd = () => { window.ev.push(['end', performance.now(), e.currentSong && e.currentSong.title]); onEnd(); };
  e.onPlay = () => { window.ev.push(['play', performance.now(), e.currentSong && e.currentSong.title]); onPlay(); }; })()`);
const nextSongCalls = () => requests.filter((r) => r.url.includes("/next_song")).length;

await js("window.ajbPlayer.play()");
await sleep(4000);
const first = await js("window.ajbPlayer.audioEngine.currentSong && window.ajbPlayer.audioEngine.currentSong.title");
check("a song is playing", !!first && await js("window.ajbPlayer.audioEngine.isPlaying"), first);
const callsAtStart = nextSongCalls();

// jump to 30s before the end: nothing may be taken yet
const dur = await js("window.ajbPlayer.audioEngine.getDuration()");
await js(`window.ajbPlayer.audioEngine.seek(${dur - 30})`);
await sleep(4000);
check("nothing taken 26s before the end", nextSongCalls() === callsAtStart && !(await js("window.ajbPlayer.audioEngine.hasPreloaded()")));
await sleep(9000);
check("the next song is taken and loading in the last 20s", nextSongCalls() === callsAtStart + 1 && await js("window.ajbPlayer.audioEngine.hasPreloaded()"));
const lined = await js("window.ajbPlayer.audioEngine.preloadedSong().title");
const shown = await js("(window.ajbPlayer.queue[0] || {}).source + ':' + ((window.ajbPlayer.queue[0] || {}).song || {}).title");
check("it is shown first in 'up next'", shown === `lined_up:${lined}`, shown);
const diag = await js("JSON.stringify(window.ajbPlayer.audioEngine.getDiagnostics().next)");
console.log("       next-song diagnostics:", diag);

// let the song end
for (let i = 0; i < 30 && (await js("window.ajbPlayer.audioEngine.currentSong.title")) === first; i++) await sleep(1000);
await sleep(1500);
const ev = await js("window.ev");
const end = ev.findLast((e) => e[0] === "end"), play = ev.findLast((e) => e[0] === "play");
const gap = end && play ? play[1] - end[1] : null;
check("the lined-up song plays next", (await js("window.ajbPlayer.audioEngine.currentSong.title")) === lined, lined);
check("it came from the preload, not a fetch at the end", nextSongCalls() === callsAtStart + 1);
check("gap between songs under 250 ms", gap !== null && gap < 250, gap !== null ? `${gap.toFixed(0)} ms` : "(no end/play seen)");

// skip mid-song: fetched on the spot
const before = nextSongCalls();
await js("window.ajbPlayer.skip()");
await sleep(3000);
check("a skip mid-song fetches and plays a new song", nextSongCalls() === before + 1 && await js("window.ajbPlayer.audioEngine.isPlaying"));

// skip right after a prefetch: the prefetched song is used, nothing else is taken
const d2 = await js("window.ajbPlayer.audioEngine.getDuration()");
await js(`window.ajbPlayer.audioEngine.seek(${d2 - 15})`);
await sleep(3000);
const lined2 = await js("window.ajbPlayer.audioEngine.hasPreloaded() && window.ajbPlayer.audioEngine.preloadedSong().title");
const calls2 = nextSongCalls();
await js("window.ajbPlayer.skip()");
await sleep(3000);
check("a skip after the prefetch plays the prefetched song", !!lined2 && (await js("window.ajbPlayer.audioEngine.currentSong.title")) === lined2 && nextSongCalls() === calls2, lined2 || "(nothing prefetched)");

// The download of the next song has not finished when this one ends (slow network): it is streamed
// instead, from the same element, and must still start by itself.
await js("window.ajbPlayer.audioEngine.downloadAhead = false");
const d3 = await js("window.ajbPlayer.audioEngine.getDuration()");
const third = await js("window.ajbPlayer.audioEngine.currentSong.title");
await js(`window.ajbPlayer.audioEngine.seek(${d3 - 12})`);
await sleep(3000);
const unbuffered = await js("JSON.stringify(window.ajbPlayer.audioEngine.getDiagnostics().next || null)");
for (let i = 0; i < 20 && (await js("window.ajbPlayer.audioEngine.currentSong.title")) === third; i++) await sleep(1000);
await sleep(2500);
const ev3 = await js("window.ev");
const end3 = ev3.findLast((e) => e[0] === "end"), play3 = ev3.findLast((e) => e[0] === "play");
const gap3 = end3 && play3 && play3[1] > end3[1] ? play3[1] - end3[1] : null;
check("with the next song not downloaded yet it is streamed and still starts by itself",
      (await js("window.ajbPlayer.audioEngine.isPlaying")) && (await js("window.ajbPlayer.audioEngine.currentSong.title")) !== third,
      `gap ${gap3 !== null ? gap3.toFixed(0) + " ms" : "?"}; next was ${unbuffered}`);

check("still one audio element after all that", (await js("document.querySelectorAll('audio').length")) === 1);
const errors = await js("JSON.stringify(window.ajbPlayer.audioEngine.getDiagnostics())");
console.log("       diagnostics now:", errors);
await js("window.ajbPlayer.audioEngine.stop()");
console.log(failed ? `BROWSER E2E FAILED (${failed})` : "BROWSER E2E PASSED");
process.exit(failed ? 1 : 0);

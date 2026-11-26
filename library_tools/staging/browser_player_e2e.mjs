// Drives the browser jukebox player in headless Chrome on staging across real song changes. Run
// through browser_player_e2e.sh (it sets everything up). AJB_OPTS=... picks the hand-over variant
// (see AudioEngine, ?ajb=).
//
// Checks: one <audio> element and the page's build; the next song is always the head of the queue,
// known before it is needed, and a request made mid-song takes its place; at the end it starts
// without asking the archive for anything, then is taken out of the queue; the gap between songs;
// skips; and a song change while the page's API calls are held back (a backgrounded iPhone Safari
// does that for minutes; the media still loads).
// Cannot check iOS itself: no lock screen, no iOS audio rules.
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const BASE = process.env.BASE || "http://127.0.0.1:3909";
const { JUKEBOX, EMAIL, PASSWORD, REQUEST_SONG } = process.env;
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
const calls = (part) => requests.filter((r) => r.url.includes(part)).length;
const E = "window.ajbPlayer.audioEngine";
const title = () => js(`${E}.currentSong && ${E}.currentSong.title`);
const nextTitle = () => js(`${E}.hasPreloaded() ? ${E}.preloadedSong().title : null`);
const queueHead = () => js("((window.ajbPlayer.queue || []).find((i) => i.source !== 'lined_up') || {song: {}}).song.title");
async function untilChange(from, seconds) { for (let i = 0; i < seconds && (await title()) === from; i++) await sleep(1000); }
function lastGap(ev) {
  const end = ev.findLast((e) => e[0] === "end"), play = ev.findLast((e) => e[0] === "play");
  return end && play && play[1] > end[1] ? play[1] - end[1] : null;
}
await send("Network.enable"); await send("Page.enable");

await go(`${BASE}/login`);
await js(`(() => { const f = document.querySelector('form'); f.querySelector('[name=email]').value = ${JSON.stringify(EMAIL)};
  f.querySelector('[name=password]').value = ${JSON.stringify(PASSWORD)}; f.submit(); })()`);
await sleep(2500);
await go(`${BASE}/jukeboxes/${JUKEBOX}/player${process.env.AJB_OPTS ? "?ajb=" + process.env.AJB_OPTS : ""}`);
check("player page has its controller", await js("!!window.ajbPlayer"));
const build = await js("window.AJB_BUILD");
check("the page reports its player build", /^[0-9a-f]{10}$/.test(build || ""), build);
console.log("       options:", await js(`${E}.getDiagnostics().opts`));
check("one audio element, no Howler", (await js("typeof Howl")) === "undefined" && (await js("document.querySelectorAll('audio').length")) === 1);
await js(`(() => { const e = ${E}; window.ev = [];
  const onEnd = e.onEnd, onPlay = e.onPlay;
  e.onEnd = () => { window.ev.push(['end', performance.now(), e.currentSong && e.currentSong.title]); onEnd(); };
  e.onPlay = () => { window.ev.push(['play', performance.now(), e.currentSong && e.currentSong.title]); onPlay(); }; })()`);

// the first song. A new jukebox's queue is empty until something asks for a song: the first Play
// does (next_song fills it). Then stop, and Play again from a filled queue.
await js("window.ajbPlayer.play()");
await sleep(4000);
check("Play on an empty queue fills it and starts a song", !!(await title()) && await js(`${E}.isPlaying`), await title());
await js("window.ajbPlayer.stop()");
await js("window.ajbPlayer.audioEngine.currentSong = null; window.ajbPlayer.playbackState.setCurrentSong(null)");
await js("window.ajbPlayer.loadQueue()");
await sleep(1500);
const head = await queueHead();
check("before playing, the next song is already known: the head of the queue", !!head && (await nextTitle()) === head, head);
const takes0 = calls("/take_song");
await js("window.ajbPlayer.play()");
await sleep(4000);
const first = await title();
check("Play starts the head of the queue", first === head && await js(`${E}.isPlaying`), first);
check("it is taken out of the queue once it started", (await queueHead()) !== first && calls("/take_song") === takes0 + 1);
check("and the song after it is known straight away", !!(await nextTitle()) && (await nextTitle()) === (await queueHead()), await nextTitle());

// a request mid-song becomes the next song
await js(`fetch('/api/v1/jukeboxes/${JUKEBOX}/queue', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json',
  'Authorization': 'Bearer ' + window.AJB_CONFIG.apiToken }, body: JSON.stringify({ song_id: ${JSON.stringify(REQUEST_SONG)}, source: 'requested' }) }).then((r) => r.status)`);
await js("window.ajbPlayer.loadQueue()");
await sleep(1500);
const requested = await nextTitle();
check("a request made mid-song is the next song", (await queueHead()) === requested && requested !== null, requested);

// the end: the request starts, without asking the archive for anything
const nextSongCallsBefore = calls("/next_song");
const dur = await js(`${E}.getDuration()`);
await js(`${E}.seek(${dur - 4})`);
await untilChange(first, 15);
await sleep(1500);
check("at the end the request plays", (await title()) === requested, await title());
check("no next_song call was needed", calls("/next_song") === nextSongCallsBefore);
const gap = lastGap(await js("window.ev"));
check("gap between songs under 250 ms", gap !== null && gap < 250, gap !== null ? `${gap.toFixed(0)} ms` : "(no end/play seen)");
await sleep(2000);
check("the request is out of the queue and the next one is known", (await queueHead()) !== requested && (await nextTitle()) === (await queueHead()), await nextTitle());

// skip mid-song: the known next song, at once
const lined = await nextTitle();
await js("window.ajbPlayer.skip()");
await sleep(2500);
check("a skip mid-song plays the known next song", (await title()) === lined && await js(`${E}.isPlaying`), lined);

// the page's API calls held back across the end of a song (backgrounded iPhone Safari)
const cur = await title(), expected = await nextTitle();
await send("Network.setBlockedURLs", { urls: ["*/api/v1/jukeboxes/*"] });   // the archive's calls; the song stream still loads
const d2 = await js(`${E}.getDuration()`);
await js(`${E}.seek(${d2 - 4})`);
await untilChange(cur, 15);
await sleep(1500);
check("with the archive unreachable, the song still changes to the known next one", (await title()) === expected && await js(`${E}.isPlaying`), expected);
const takesBefore = await js("(window.ajbPlayer.takingSongIds || []).length");
await send("Network.setBlockedURLs", { urls: [] });
for (let i = 0; i < 20 && (await js("(window.ajbPlayer.takingSongIds || []).length")) > 0; i++) await sleep(1000);
check("once it is back, the archive is told", takesBefore > 0 && (await js("(window.ajbPlayer.takingSongIds || []).length")) === 0 && (await queueHead()) !== expected);

check("still one audio element after all that", (await js("document.querySelectorAll('audio').length")) === 1);
console.log("       diagnostics now:", await js(`JSON.stringify(${E}.getDiagnostics())`));
await js(`${E}.stop()`);
console.log(failed ? `BROWSER E2E FAILED (${failed})` : "BROWSER E2E PASSED");
process.exit(failed ? 1 : 0);

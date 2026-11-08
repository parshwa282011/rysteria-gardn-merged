#!/usr/bin/env node
// Makes the pictures of the web pages with the games themselves.
//
//   node scripts/gen-icons.mjs [--rrolf DIR] --gardn DIR [--out DIR] [--chrome PATH]
//
// DIR is a folder with a built client (index.html, the .js and .wasm). Gardn's client has
// a hidden mode: the page opened with ?iconsheet draws every petal, as its loadout does,
// instead of playing (gardn/Client/IconSheet.cc). This script opens that in headless
// Chrome at double resolution and saves what is drawn to rrolf/Client/public/icons/
// (the stats pages are served from there):
//
//   gardn-petals.png      column = id % 12, row = id / 12, tiles of 128 px
//   rysteria-petals.png   (only with --rrolf, a build that has the mode) column = petal id,
//                         row = rarity, tiles of 128 px
//
// The petals only, without a tile or a name: the stats pages put the rarity colour behind
// them. With python3 and Pillow the pictures are also squeezed to 256 colours (a quarter
// of the size).
//
// Run it again after a change to how a petal looks. Chrome is looked for at the usual
// places, or give it with --chrome or the CHROME environment variable.
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith("--") ? [...a, [v.slice(2), all[i + 1]]] : a), []));
const out = args.out || path.join(here, "..", "rrolf", "Client", "public", "icons");
const rrolfDir = args.rrolf, gardnDir = args.gardn;
if (!gardnDir) {
    console.error("usage: node scripts/gen-icons.mjs [--rrolf DIR] --gardn DIR [--out DIR] [--chrome PATH]");
    process.exit(2);
}
const chromePath = args.chrome || process.env.CHROME || [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
].find(existsSync);
if (!chromePath) { console.error("Chrome was not found: use --chrome"); process.exit(2); }
mkdirSync(out, { recursive: true });

const types = { ".html": "text/html", ".js": "application/javascript", ".wasm": "application/wasm", ".png": "image/png", ".ico": "image/x-icon" };
const server = http.createServer((req, res) => {
    let p = decodeURIComponent(req.url.split("?")[0]);
    let root = rrolfDir || gardnDir;
    if (p === "/gardn" || p.startsWith("/gardn/")) { root = gardnDir; p = p.slice(6) || "/"; }
    if (p === "/" || p === "") p = "/index.html";
    const file = path.join(root, path.normalize(p));
    if (!file.startsWith(path.resolve(root)) || !existsSync(file)) { res.writeHead(404).end(); return; }
    res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" }).end(readFileSync(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = "http://127.0.0.1:" + server.address().port;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const profile = path.join(process.env.TMPDIR || "/tmp", "gen-icons-profile-" + process.pid);
const chrome = spawn(chromePath, ["--headless=new", "--remote-debugging-port=9347", "--user-data-dir=" + profile, "--no-first-run",
    "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "about:blank"], { stdio: "ignore" });
let tabs;
for (let i = 0; i < 80; i++) { try { tabs = await (await fetch("http://127.0.0.1:9347/json")).json(); if (tabs.length) break; } catch (e) {} await sleep(250); }
const ws = new WebSocket(tabs.find((t) => t.type === "page").webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0; const waiting = new Map();
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id); } };
const send = (method, params = {}) => new Promise((r) => { const i = ++id; waiting.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send("Page.enable"); await send("Runtime.enable");
// gardn goes to the log in page when it finds no login, the picture needs none
await send("Page.addScriptToEvaluateOnNewDocument", { source: "window.gardnLogin={uuid:'',plp:''}; try{localStorage['uuid']='00000000-0000-4000-8000-000000000000';localStorage['PL-P']='x';localStorage['PL-T']='x';}catch(e){}" });

// opens the page, waits for the game to draw, and saves a part of the canvas as a png
async function shot(url, width, height, parts) {
    await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 2, mobile: false });
    await send("Page.navigate", { url });
    await sleep(7000);
    for (const [name, x, y, w, h] of parts) {
        const r = await send("Runtime.evaluate", {
            returnByValue: true,
            expression: `(() => { const c = document.querySelector("canvas"); const o = document.createElement("canvas"); o.width = ${w}; o.height = ${h};
                o.getContext("2d").drawImage(c, ${x}, ${y}, ${w}, ${h}, 0, 0, ${w}, ${h}); return o.toDataURL("image/png"); })()`,
        });
        const data = r.result.result && r.result.result.value;
        if (!data || !data.startsWith("data:image/png")) throw new Error("no picture for " + name + ": " + JSON.stringify(r.result));
        writeFileSync(path.join(out, name), Buffer.from(data.split(",")[1], "base64"));
        squeeze(path.join(out, name));
        console.log("wrote", path.join(out, name), w + "x" + h);
    }
}

import { execFileSync } from "node:child_process";
function squeeze(file) {
    try {
        execFileSync("python3", ["-c", "import sys; from PIL import Image; f = sys.argv[1]; Image.open(f).convert('RGBA').quantize(colors=256, method=Image.Quantize.FASTOCTREE).save(f, optimize=True)", file]);
    } catch (e) { console.log("(not squeezed: python3 with Pillow is needed)"); }
}

// the games say how many tiles there are (window.iconSheetInfo), so nothing here has to
// change when a petal is added
async function sheetInfo() {
    const r = await send("Runtime.evaluate", { returnByValue: true, expression: "window[\"iconSheetInfo\"]" });
    const info = r.result.result && r.result.result.value;
    if (!info) throw new Error("the game did not draw its icons (is it a build with the ?iconsheet mode?)");
    return info;
}

try {
    if (rrolfDir) {
        // Rysteria: a column for every petal id, a row for every rarity, tiles of 64 css px
        await send("Emulation.setDeviceMetricsOverride", { width: 3000, height: 800, deviceScaleFactor: 2, mobile: false });
        await send("Page.navigate", { url: base + "/?iconsheet" });
        await sleep(7000);
        const info = await sheetInfo();
        console.log("Rysteria:", JSON.stringify(info));
        await shot(base + "/?iconsheet", info.columns * 64 + 100, info.rows * 64 + 100,
            [["rysteria-petals.png", 0, 0, info.columns * 128, info.rows * 128]]);
    }
    // gardn: the petals in rows of 12
    await send("Emulation.setDeviceMetricsOverride", { width: 1200, height: 800, deviceScaleFactor: 2, mobile: false });
    await send("Page.navigate", { url: base + "/gardn/?iconsheet" });
    await sleep(7000);
    const info = await sheetInfo();
    console.log("gardn:", JSON.stringify(info));
    await shot(base + "/gardn/?iconsheet", info.columns * 64 + 100, info.rows * 64 + 100,
        [["gardn-petals.png", 0, 0, info.columns * 128, info.rows * 128]]);
} finally {
    chrome.kill();
    server.close();
}
process.exit(0);

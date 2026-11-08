#!/usr/bin/env node
// Makes the picture of every petal for the web pages (the stats pages) with the games
// themselves. scripts/common/build.sh runs it after the clients are built.
//
//   node scripts/gen-icons.mjs --rrolf DIR --gardn DIR --out DIR [--chrome PATH]
//
// DIR is the folder of a built client (index.html, the .js and .wasm): builds/<os>/rrolf-client
// and builds/<os>/gardn. Both clients have a hidden mode: the page opened with ?iconsheet
// draws every petal the way its loadout does, without the tile and the name, instead of
// playing (rrolf/Client/Main.c, gardn/Client/IconSheet.cc). This script opens that in
// headless Chrome at double resolution and cuts every petal out as its own png (128 px,
// transparent: the pages put the rarity colour behind it):
//
//   OUT/rysteria/<petal id>-<rarity>.png     (the petal looks different at each rarity)
//   OUT/gardn/<petal id>.png
//
// The pages ask for /icons/rysteria/.. and /icons/gardn/.., so OUT is <client folder>/icons.
// Without Chrome (or when the games do not draw) nothing is written and the exit code is
// 1: the build only warns, the pages show the plain coloured tile.
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";
import path from "node:path";

const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => (v.startsWith("--") ? [...a, [v.slice(2), all[i + 1]]] : a), []));
const rrolfDir = args.rrolf, gardnDir = args.gardn, out = args.out;
if (!rrolfDir || !gardnDir || !out) {
    console.error("usage: node scripts/gen-icons.mjs --rrolf DIR --gardn DIR --out DIR [--chrome PATH]");
    process.exit(2);
}
const chromePath = args.chrome || process.env.CHROME || [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/usr/bin/chromium", "/usr/bin/chromium-browser",
].find(existsSync);
if (!chromePath) { console.error("gen-icons: Chrome was not found (--chrome PATH or CHROME)"); process.exit(1); }

const types = { ".html": "text/html", ".js": "application/javascript", ".wasm": "application/wasm", ".png": "image/png", ".ico": "image/x-icon", ".txt": "text/plain" };
const server = http.createServer((req, res) => {
    let p = decodeURIComponent(req.url.split("?")[0]);
    let root = rrolfDir;
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
const chrome = spawn(chromePath, ["--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + profile, "--no-first-run",
    "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
// Chrome says where its debugging port is on stderr
const port = await new Promise((resolve, reject) => {
    let log = "";
    chrome.stderr.on("data", (d) => { log += d; const m = /DevTools listening on ws:\/\/127\.0\.0\.1:(\d+)\//.exec(log); if (m) resolve(+m[1]); });
    chrome.on("exit", () => reject(new Error("Chrome stopped: " + log.slice(-300))));
    setTimeout(() => reject(new Error("Chrome did not start")), 30000);
}).catch((e) => { console.error("gen-icons: " + e.message); chrome.kill(); server.close(); process.exit(1); });

let exitCode = 0;
try {
    const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
    const ws = new WebSocket(tabs.find((t) => t.type === "page").webSocketDebuggerUrl);
    await new Promise((r) => (ws.onopen = r));
    let id = 0; const waiting = new Map();
    ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id); } };
    const send = (method, params = {}) => new Promise((r) => { const i = ++id; waiting.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
    await send("Page.enable"); await send("Runtime.enable");
    // gardn goes to the log in page when it finds no login, the picture needs none
    await send("Page.addScriptToEvaluateOnNewDocument", { source: "window.gardnLogin={uuid:'',plp:''}; try{localStorage['uuid']='00000000-0000-4000-8000-000000000000';localStorage['PL-P']='x';localStorage['PL-T']='x';}catch(e){}" });

    // opens the sheet of a game and returns what it says about it (window.iconSheetInfo)
    async function open(url, width) {
        await send("Emulation.setDeviceMetricsOverride", { width, height: 900, deviceScaleFactor: 2, mobile: false });
        await send("Page.navigate", { url });
        for (let i = 0; i < 40; i++) {
            await sleep(500);
            const r = await send("Runtime.evaluate", { returnByValue: true, expression: 'window["iconSheetInfo"]' });
            if (r.result.result && r.result.result.value) { await sleep(1500); return r.result.result.value; }
        }
        throw new Error("the game at " + url + " did not draw its icons (is it a build with the ?iconsheet mode?)");
    }
    // Every tile cut out of the canvas, as png data: [[name, dataUrl], ...]. The petals
    // are drawn at the size they have in the game, so the single ones are small next to
    // the clumps: all the tiles of a sheet are scaled up by the same amount, until the
    // widest one (measured from the centre of its tile) nearly fills it.
    async function cut(tiles, size) {
        const r = await send("Runtime.evaluate", {
            returnByValue: true,
            expression: `(() => { const c = document.querySelector("canvas"); const S = ${size};
                const t = document.createElement("canvas"); t.width = t.height = S; const tx = t.getContext("2d", { willReadFrequently: true });
                const o = document.createElement("canvas"); o.width = o.height = S; const ox = o.getContext("2d");
                const list = ${JSON.stringify(tiles)};
                let reach = 1;
                for (const [name, sx, sy] of list) {
                    tx.clearRect(0, 0, S, S); tx.drawImage(c, sx, sy, S, S, 0, 0, S, S);
                    const d = tx.getImageData(0, 0, S, S).data;
                    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++)
                        if (d[(y * S + x) * 4 + 3] > 8) reach = Math.max(reach, Math.abs(x + 0.5 - S / 2), Math.abs(y + 0.5 - S / 2));
                }
                const k = (S / 2 * 0.94) / reach;
                return list.map(([name, sx, sy]) => { ox.clearRect(0, 0, S, S); ox.save(); ox.translate(S / 2, S / 2); ox.scale(k, k);
                    ox.drawImage(c, sx, sy, S, S, -S / 2, -S / 2, S, S); ox.restore(); return [name, o.toDataURL("image/png")]; }); })()`,
        });
        if (!r.result.result || !Array.isArray(r.result.result.value)) throw new Error("no picture: " + JSON.stringify(r.result));
        return r.result.result.value;
    }
    function save(dir, list) {
        mkdirSync(path.join(out, dir), { recursive: true });
        for (const [name, data] of list) writeFileSync(path.join(out, dir, name), Buffer.from(data.split(",")[1], "base64"));
        console.log("gen-icons: " + list.length + " icons in " + path.join(out, dir));
    }

    // Rysteria: a column for every petal id, a row for every rarity
    let info = await open(base + "/?iconsheet", 3000);
    let tiles = [];
    for (let rarity = 0; rarity < info.rows; ++rarity)
        for (let petal = 1; petal < info.columns; ++petal)
            tiles.push([`${petal}-${rarity}.png`, petal * info.cell * 2, rarity * info.cell * 2]);
    save("rysteria", await cut(tiles, info.cell * 2));

    // gardn: 12 to a row
    info = await open(base + "/gardn/?iconsheet", 1200);
    tiles = [];
    for (let petal = 1; petal < info.count; ++petal)
        tiles.push([`${petal}.png`, (petal % info.columns) * info.cell * 2, Math.floor(petal / info.columns) * info.cell * 2]);
    save("gardn", await cut(tiles, info.cell * 2));
} catch (e) {
    console.error("gen-icons: " + e.message);
    exitCode = 1;
} finally {
    chrome.kill();
    server.close();
}
process.exit(exitCode);

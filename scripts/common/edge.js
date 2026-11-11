// Public web server for game.<domain>.
//   /          the rrolf client (static files from CLIENT_DIR)
//   /login, /signup      log in, sign up, confirm the email, reset (login.html); both games send
//                        everybody without a valid login here
//   /account             link Discord/Google/Apple, add an email, delete the account (account.html)
//   /privacy, /terms     privacy policy and terms of service (Google/Apple/store listings ask for URLs)
//   /leaderboard         Parteria leaderboards (leaderboard.html next to the client)
//   /stats?uuid=...      a player's stats, with a search for others (stats.html)
//   /status              the stats of the player who is logged in (stats.html)
//   /gardn/leaderboard   gardn leaderboards (the same leaderboard.html)
//   /gardn/stats         the gardn petal statistics (gardn-stats.html)
//   /gardn/*   gardn: its page, client files and websocket, forwarded to the
//              gardn server with the /gardn prefix removed
//   /health    liveness
// Settings come from ./.env (EDGE_PORT, CLIENT_DIR, GARDN_PORT) or the
// environment. No dependencies: plain node.

const http = require("http");
const net = require("net");
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");

try {
    for (const line of fs.readFileSync(".env", "utf8").split("\n")) {
        const i = line.indexOf("=");
        if (i <= 0 || line.startsWith("#")) continue;
        const key = line.slice(0, i).trim();
        if (process.env[key] === undefined) process.env[key] = line.slice(i + 1).trim();
    }
} catch (e) {}

const PORT = Number(process.env.EDGE_PORT) || 8080;
const GARDN_PORT = Number(process.env.GARDN_PORT) || 9001;
const CLIENT_DIR = path.resolve(process.env.CLIENT_DIR || "rrolf-client");
// run (through sh) when gardn does not answer, at most once every minute: it starts gardn
// again (scripts/common/restart-one.sh gardn). Unset = never
const GARDN_RESTART_COMMAND = process.env.GARDN_RESTART_COMMAND || "";
const GARDN_RESTART_COOLDOWN_MS = 60 * 1000;
let lastGardnRestart = 0;

function gardnIsDown() {
    const now = Date.now();
    if (!GARDN_RESTART_COMMAND || now - lastGardnRestart < GARDN_RESTART_COOLDOWN_MS) return;
    lastGardnRestart = now;
    console.log("gardn does not answer: starting it again");
    execFile("/bin/sh", ["-c", GARDN_RESTART_COMMAND], { timeout: 60000 }, (err, stdout, stderr) => {
        if (err) console.log(`restarting gardn failed (${err.code}): ${(stderr || stdout || err.message).trim().split("\n").slice(-2).join(" | ")}`);
        else console.log("gardn started again");
    });
}

const TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".json": "application/json",
    ".txt": "text/plain; charset=utf-8",
};

// pages of ours, by path. The gardn ones sit under /gardn/ but are not gardn's
const PAGES = {
    "/privacy": "/privacy.html",
    "/privacy-policy": "/privacy.html",
    "/terms": "/terms.html",
    "/terms-of-service": "/terms.html",
    "/account": "/account.html",
    "/login": "/login.html",
    "/signup": "/login.html",
    "/leaderboard": "/leaderboard.html",
    "/gardn/leaderboard": "/leaderboard.html",
    "/stats": "/stats.html",
    "/status": "/stats.html",
    "/gardn/stats": "/gardn-stats.html",
};

function pathOf(url) {
    return url.split("?")[0].split("#")[0];
}

function serveStatic(req, res) {
    let pathname;
    try {
        pathname = decodeURIComponent(pathOf(req.url));
    } catch (e) {
        // "/%zz" must not take the whole site down
        res.writeHead(400, { "content-type": "text/plain" }).end("bad request\n");
        return;
    }
    if (pathname === "/") pathname = "/index.html";
    else if (PAGES[pathname.replace(/\/+$/, "")]) pathname = PAGES[pathname.replace(/\/+$/, "")];
    const file = path.join(CLIENT_DIR, path.normalize(pathname));
    if (!file.startsWith(CLIENT_DIR + path.sep)) {
        res.writeHead(403).end();
        return;
    }
    fs.stat(file, (statErr, stat) => {
        if (statErr || !stat.isFile()) {
            res.writeHead(404, { "content-type": "text/plain" }).end("not found\n");
            return;
        }
        // The client must always be the build the servers speak: the browser asks again every time
        // and gets a 304 (no body) while the file is unchanged. A cache of an hour kept the previous
        // client alive for an hour after an update, and it can not read the new server's packets.
        const etag = `W/"${stat.size}-${Math.floor(stat.mtimeMs)}"`;
        if (req.headers["if-none-match"] === etag) {
            res.writeHead(304, { etag, "cache-control": "no-cache" }).end();
            return;
        }
        fs.readFile(file, (err, data) => {
            if (err) {
                res.writeHead(404, { "content-type": "text/plain" }).end("not found\n");
                return;
            }
            // the client is built as "rrolf-client" (no extension) for the page's
            // <script src="rrolf-client">
            const type = TYPES[path.extname(file)] || (file.endsWith("rrolf-client") ? TYPES[".js"] : "application/octet-stream");
            res.writeHead(200, { "content-type": type, "cache-control": "no-cache", etag });
            res.end(data);
        });
    });
}

// the gardn host matches the exact path, so drop the prefix and the query
// (nginx did that for the original deployment)
function gardnPath(url) {
    const p = pathOf(url).slice("/gardn".length);
    return p === "" ? "/" : p;
}

function proxyHttp(req, res) {
    const upstream = http.request({ host: "127.0.0.1", port: GARDN_PORT, method: req.method, path: gardnPath(req.url), headers: { ...req.headers, host: "127.0.0.1" } }, (up) => {
        res.writeHead(up.statusCode, up.headers);
        up.pipe(res);
    });
    upstream.on("error", () => {
        gardnIsDown();
        if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
        res.end("gardn is down\n");
    });
    req.pipe(upstream);
}

const server = http.createServer((req, res) => {
    const p = pathOf(req.url);
    if (p === "/health") {
        res.writeHead(200, { "content-type": "application/json" }).end('{"ok":true}');
    } else if (p === "/gardn") {
        // gardn's page links its files relatively (gardn-client.js): without the
        // slash they would be requested from the site root and 404
        const q = req.url.indexOf("?");
        res.writeHead(302, { location: "/gardn/" + (q >= 0 ? req.url.slice(q) : "") }).end();
    } else if (PAGES[p.replace(/\/+$/, "")]) {
        serveStatic(req, res);
    } else if (p.startsWith("/gardn/")) {
        proxyHttp(req, res);
    } else {
        serveStatic(req, res);
    }
});

// websocket upgrades for gardn are forwarded byte for byte
server.on("upgrade", (req, socket, head) => {
    const p = pathOf(req.url);
    if (!(p === "/gardn" || p.startsWith("/gardn/"))) {
        socket.destroy();
        return;
    }
    const upstream = net.connect(GARDN_PORT, "127.0.0.1", () => {
        let header = `${req.method} ${gardnPath(req.url)} HTTP/1.1\r\n`;
        for (let i = 0; i < req.rawHeaders.length; i += 2) header += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`;
        upstream.write(header + "\r\n");
        if (head && head.length) upstream.write(head);
        socket.pipe(upstream).pipe(socket);
    });
    // whichever side goes away takes the other with it, or half open sockets pile up
    upstream.on("error", () => {
        gardnIsDown();
        socket.destroy();
    });
    upstream.on("close", () => socket.destroy());
    socket.on("error", () => upstream.destroy());
    socket.on("close", () => upstream.destroy());
});

server.listen(PORT, "127.0.0.1", () => console.log(`edge listening on 127.0.0.1:${PORT}, client ${CLIENT_DIR}, gardn :${GARDN_PORT}`));
// a bug in one request must not take the site down
process.on("uncaughtException", (e) => console.error("edge: uncaught " + (e && e.stack || e)));
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => process.exit(0));

// Public web server for game.<domain>.
//   /          the rrolf client (static files from CLIENT_DIR)
//   /gardn/*   gardn: its page, client files and websocket, forwarded to the
//              gardn server with the /gardn prefix removed
//   /health    liveness
// Settings come from ./.env (EDGE_PORT, CLIENT_DIR, GARDN_PORT) or the
// environment. No dependencies: plain node.

const http = require("http");
const net = require("net");
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

const TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".png": "image/png",
    ".json": "application/json",
    ".txt": "text/plain; charset=utf-8",
};

function pathOf(url) {
    return url.split("?")[0].split("#")[0];
}

function serveStatic(req, res) {
    let pathname = decodeURIComponent(pathOf(req.url));
    if (pathname === "/") pathname = "/index.html";
    const file = path.join(CLIENT_DIR, path.normalize(pathname));
    if (!file.startsWith(CLIENT_DIR + path.sep)) {
        res.writeHead(403).end();
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
        res.writeHead(200, { "content-type": type, "cache-control": file.endsWith(".html") ? "no-cache" : "public, max-age=3600" });
        res.end(data);
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
    upstream.on("error", () => res.writeHead(502, { "content-type": "text/plain" }).end("gardn is down\n"));
    req.pipe(upstream);
}

const server = http.createServer((req, res) => {
    const p = pathOf(req.url);
    if (p === "/health") {
        res.writeHead(200, { "content-type": "application/json" }).end('{"ok":true}');
    } else if (p === "/gardn" || p.startsWith("/gardn/")) {
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
    upstream.on("error", () => socket.destroy());
    socket.on("error", () => upstream.destroy());
});

server.listen(PORT, "127.0.0.1", () => console.log(`edge listening on 127.0.0.1:${PORT}, client ${CLIENT_DIR}, gardn :${GARDN_PORT}`));
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => process.exit(0));

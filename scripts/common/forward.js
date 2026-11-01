'use strict';
// A plain TCP forwarder, for split mode: the tunnel on this machine sends the
// hostnames of the other machine's game servers to 127.0.0.1:<port> like every
// other server, and this passes each connection on to <target host>:<port> on the
// other machine. Nothing in it knows about HTTP or websockets, they just pass.
//
//   node forward.js <listen host> <listen port> <target host> <target port>
const net = require('net');

const [listenHost, listenPort, targetHost, targetPort] = process.argv.slice(2);
if (!listenHost || !(+listenPort > 0) || !targetHost || !(+targetPort > 0)) {
    console.error('usage: node forward.js <listen host> <listen port> <target host> <target port>');
    process.exit(2);
}
const log = (msg) => console.log(`${new Date().toISOString()} ${msg}`);
let open = 0;
let failures = 0;
let lastFailLog = 0;

const server = net.createServer((client) => {
    const upstream = net.connect({ host: targetHost, port: +targetPort });
    ++open;
    let closed = false;
    const end = (why) => {
        if (closed) return;
        closed = true;
        --open;
        client.destroy();
        upstream.destroy();
        // a target that is down fails every connection: say so once a minute, not every time
        if (why && Date.now() - lastFailLog > 60000) {
            lastFailLog = Date.now();
            log(`${targetHost}:${targetPort} ${why} (${++failures} failed connections so far)`);
        } else if (why) {
            ++failures;
        }
    };
    for (const s of [client, upstream]) {
        s.setNoDelay(true);
        s.setKeepAlive(true, 30000); // a target that vanished is noticed
    }
    client.on('error', () => end());
    upstream.on('error', (e) => end(e.code || e.message));
    client.on('close', () => end());
    upstream.on('close', () => end());
    client.pipe(upstream);
    upstream.pipe(client);
});
server.on('error', (e) => {
    console.error(`cannot listen on ${listenHost}:${listenPort}: ${e.message}`);
    process.exit(1);
});
server.listen(+listenPort, listenHost, () => log(`${listenHost}:${listenPort} -> ${targetHost}:${targetPort}`));
setInterval(() => open > 0 && log(`${open} open connections`), 10 * 60 * 1000).unref();
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => process.exit(0));
process.on('uncaughtException', (e) => log(`error: ${e.message}`));

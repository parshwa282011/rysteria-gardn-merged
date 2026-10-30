'use strict';
process.on('uncaughtException', (e) => {
    console.error(`syncd: ${e.message}`);
    process.exit(1);
});
// syncd: keeps up to five machines (one primary, up to four backups) in step and
// decides who serves the game. Started by scripts/<os>/run.sh next to the other
// servers; see README.md for the rules.
//
//   node syncd.js            run the supervisor (what run.sh does)
//   node syncd.js status     show this machine's view of the cluster
//   node syncd.js promote    make this machine the primary now (planned switch)
const fs = require('fs');
const path = require('path');
const { log, sleep, loadEnv, health, describe, internetOk, sh, shq, pidAlive } = require('./util');

loadEnv(process.env.ENV_FILE || path.join(__dirname, '.env'));
const env = process.env;
const num = (key, fallback) => (env[key] && Number(env[key]) > 0 ? Number(env[key]) : fallback);

// ------------------------------------------------------------------ settings
const cfg = {
    domain: env.DOMAIN || 'parshwa.blog',
    apiHost: env.SYNC_API_HOST || 'api-game',
    port: num('MASTER_PORT', 55554),
    secret: env.CLONE_SECRET || '',
    pgUri: env.POSTGRES_URI || '',
    interval: num('SYNC_INTERVAL', 30), // seconds between checks
    probes: num('SYNC_FAIL_PROBES', 3), // failed checks (5 s apart) before a node counts as down
    stagger: num('SYNC_STAGGER', 45), // extra seconds a node waits per higher-priority node
    tunnelGrace: num('SYNC_TUNNEL_GRACE', 60), // extra wait when the primary itself is fine but its tunnel is not
    maxStale: num('SYNC_MAX_STALE', 900), // a backup older than this never promotes by itself
    rsRoot: env.RS_ROOT || path.resolve(__dirname, '..'),
    rsRun: env.RS_RUN || '',
    rsOs: env.RS_OS || '',
    nodesFile: env.SYNC_NODES_FILE || path.join(__dirname, 'nodes.conf'),
    statePath: env.SYNC_STATE_FILE || path.join(__dirname, 'sync-state.json'),
};
const PUBLIC = env.SYNC_PUBLIC_URL || `https://${cfg.apiHost}.${cfg.domain}`;
const LOCAL = `http://127.0.0.1:${cfg.port}`;
const roleFile = path.join(cfg.rsRun, 'sync.role');
const forceFile = path.join(path.dirname(cfg.statePath), 'sync-force');
const tunnelPid = path.join(cfg.rsRun, 'cloudflared.pid');

// -------------------------------------------------------------------- nodes
// name os lan ssh repo     ("-" = none)   first line = highest priority
function loadNodes() {
    let text;
    try {
        text = fs.readFileSync(cfg.nodesFile, 'utf8');
    } catch {
        throw new Error(`no node list at ${cfg.nodesFile}: copy nodes.conf.example there and edit it`);
    }
    const nodes = [];
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.replace(/#.*/, '').trim();
        if (!line) continue;
        const [name, os, lan, ssh, ...repo] = line.split(/\s+/);
        if (!name || !['macos', 'debian', 'windows'].includes(os)) {
            throw new Error(`bad line in ${cfg.nodesFile}: "${raw}" (os must be macos, debian or windows)`);
        }
        nodes.push({
            name: name.toLowerCase(),
            os,
            lan: lan && lan !== '-' ? (lan.includes(':') ? lan : `${lan}:${cfg.port}`) : '',
            ssh: ssh && ssh !== '-' ? ssh : '',
            repo: repo.join(' ').replace(/^-$/, ''),
        });
    }
    if (nodes.length > 5) throw new Error('nodes.conf lists more than 5 machines (1 primary + 4 backups)');
    return nodes;
}

const nodes = loadNodes();
const myName = (env.NODE_NAME || '').toLowerCase();
const me = nodes.find((n) => n.name === myName);
if (!me) {
    throw new Error(
        `this machine is "${myName}" but nodes.conf lists: ${nodes.map((n) => n.name).join(', ')}. ` +
            `Put its name in ~/.rysteria-secrets/sync-node (or SYNC_NODE) and run build.sh again.`,
    );
}
const rank = nodes.indexOf(me); // 0 = first choice
const byName = (name) => nodes.find((n) => n.name === (name || '').toLowerCase());

// -------------------------------------------------------------------- state
// Survives restarts and clean-builds: where we are in the primary's feed.
let state = { source: '', cursor: '', lastSync: 0, wasPrimary: false, primary: '', failures: 0 };
try {
    state = { ...state, ...JSON.parse(fs.readFileSync(cfg.statePath, 'utf8')) };
} catch {
    /* first start */
}
function saveState() {
    const tmp = `${cfg.statePath}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(state, null, 2), { mode: 0o600 });
    fs.renameSync(tmp, cfg.statePath);
}

let role = 'standby';
function setRole(r) {
    role = r;
    fs.mkdirSync(cfg.rsRun, { recursive: true });
    fs.writeFileSync(roleFile, `${r}\n`); // run.sh only starts the tunnel when this says primary
}

// ------------------------------------------------------------ local machine
const runScript = path.join(cfg.rsRoot, 'scripts', cfg.rsOs, 'run.sh');
let lastStackStart = 0;

// A standby keeps the whole game stack running (no tunnel, so nobody connects).
async function ensureLocalStack() {
    const loc = await health(`${LOCAL}/health`);
    if (loc.ok) return;
    if (Date.now() - lastStackStart < 60000) return;
    lastStackStart = Date.now();
    log(`local master is not healthy (${describe(loc)}): running run.sh`);
    const r = await sh(runScript, [], { timeout: 300000 });
    log(`run.sh exit ${r.code}: ${r.out.split('\n').slice(-3).join(' | ')}`);
}

async function killTunnel() {
    const pid = pidAlive(tunnelPid);
    if (!pid) return false;
    log(`stopping cloudflared (pid ${pid})`);
    process.kill(pid, 'SIGTERM');
    for (let i = 0; i < 16 && pidAlive(tunnelPid); i++) await sleep(500);
    if (pidAlive(tunnelPid)) process.kill(pid, 'SIGKILL');
    fs.rmSync(tunnelPid, { force: true });
    return true;
}

// ---------------------------------------------------------------- standby
const ndjson = async function* (body) {
    const dec = new TextDecoder();
    let buf = '';
    for await (const chunk of body) {
        buf += dec.decode(chunk, { stream: true });
        let i;
        while ((i = buf.indexOf('\n')) >= 0) {
            const line = buf.slice(0, i);
            buf = buf.slice(i + 1);
            if (line) yield JSON.parse(line);
        }
    }
    if (buf.trim()) yield JSON.parse(buf);
};

// One pull: first time (or after a failover) the whole database, afterwards
// only what changed since the last pull.
async function pull(pub) {
    const store = require('./store');
    const params = new URLSearchParams({ node: me.name });
    if (state.source && state.cursor) {
        params.set('since', state.cursor);
        params.set('source', state.source);
    }
    const res = await fetch(`${PUBLIC}/backup?${params}`, {
        headers: { 'x-clone-secret': cfg.secret },
        signal: AbortSignal.timeout(300000),
    });
    if (!res.ok) {
        const why = { 403: 'CLONE_SECRET differs from the primary\'s', 503: 'the primary has no CLONE_SECRET', 404: 'the primary runs an old master without /backup', 501: 'the primary uses MongoDB' }[res.status];
        throw new Error(`/backup answered HTTP ${res.status}${why ? ` (${why})` : ''}`);
    }
    const client = await store.connect(cfg.pgUri);
    try {
        const { head, count } = await store.applyFeed(client, ndjson(res.body));
        state = { ...state, source: head.source, cursor: head.next, lastSync: Date.now(), wasPrimary: false, primary: head.node || pub.node || state.primary, failures: 0 };
        saveState();
        if (head.mode === 'snapshot' || count > 0) log(`${head.mode}: ${count} rows from ${state.primary || 'the primary'}`);
    } catch (e) {
        // two failed incremental applies in a row: start over with a snapshot
        if (++state.failures >= 2) {
            state.source = state.cursor = '';
            state.failures = 0;
        }
        saveState();
        throw e;
    } finally {
        await client.end().catch(() => {});
    }
}

async function standbyTick() {
    await ensureLocalStack();
    await killTunnel(); // a standby never holds the tunnel
    if (fs.existsSync(forceFile)) {
        fs.rmSync(forceFile, { force: true });
        return promote(true);
    }
    const pub = await health(`${PUBLIC}/health`);
    if (pub.ok) {
        if (pub.node && pub.node === me.name) return; // our own tunnel, just stopped
        try {
            await pull(pub);
        } catch (e) {
            log(`sync failed: ${e.message}`);
        }
        return;
    }
    if (!(await internetOk())) {
        log('this machine is offline: not judging the primary');
        return;
    }
    await primaryDown(pub);
}

// May this machine take over without a human? Never with old data.
function eligible() {
    if (state.wasPrimary) return { ok: true };
    if (!state.lastSync) {
        return rank === 0 ? { ok: true } : { ok: false, why: 'it has never synced and is not the first-choice node' };
    }
    const age = (Date.now() - state.lastSync) / 1000;
    if (age > cfg.maxStale) return { ok: false, why: `its last sync was ${Math.round(age / 60)} min ago (SYNC_MAX_STALE=${cfg.maxStale}s); run "sync.sh promote" to override` };
    return { ok: true };
}

async function primaryDown(first) {
    let latest = first;
    for (let i = 1; i < cfg.probes; i++) {
        await sleep(5000);
        latest = await health(`${PUBLIC}/health`);
        if (latest.ok) return;
    }
    const old = byName(state.primary);
    const peer = old && old !== me && old.lan ? await health(`http://${old.lan}/health`) : null;
    // The primary answers on its own address but not through the tunnel: its own
    // syncd restarts cloudflared first, so give it a head start.
    const tunnelOnly = !!peer?.ok;
    log(`public health is failing: ${describe(latest)}` + (peer ? `; ${old.name} directly: ${describe(peer)}` : ''));
    const wait = rank * cfg.stagger + (tunnelOnly ? cfg.tunnelGrace : 0);
    if (wait) log(`waiting ${wait}s (priority ${rank + 1} of ${nodes.length}${tunnelOnly ? ', tunnel-only fault' : ''}) in case a better node takes over`);
    const until = Date.now() + wait * 1000;
    while (Date.now() < until) {
        await sleep(5000);
        if ((await health(`${PUBLIC}/health`)).ok) {
            log('public health is back: someone else took over');
            return;
        }
    }
    const e = eligible();
    if (!e.ok) {
        log(`NOT taking over: ${e.why}`);
        return;
    }
    await promote(false);
}

// -------------------------------------------------------- taking over / fencing
async function fence(old) {
    if (!old.ssh) return log(`no ssh address for ${old.name}: cannot stop it, continuing`);
    const remote =
        old.os === 'windows'
            ? `powershell -NoProfile -ExecutionPolicy Bypass -File "${old.repo}\\scripts\\windows\\stop.ps1"`
            : `bash -lc ${shq(`cd ${shq(old.repo)} && scripts/${old.os}/stop.sh`)}`;
    log(`stopping ${old.name} over ssh (${old.ssh})`);
    const r = await sh('ssh', ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=accept-new', old.ssh, remote], { timeout: 150000 });
    if (r.code === 0) log(`${old.name} is stopped`);
    else log(`could not stop ${old.name} (ssh exit ${r.code}${r.timedOut ? ', timed out' : ''}): ${r.out.split('\n').slice(-2).join(' | ')}; taking over anyway`);
}

async function promote(forced) {
    const loc = await health(`${LOCAL}/health`);
    if (!loc.ok) {
        log(`cannot take over: the local master is not healthy (${describe(loc)})`);
        return;
    }
    const old = byName(state.primary);
    if (old && old !== me) await fence(old);

    const store = require('./store');
    const client = await store.connect(cfg.pgUri);
    try {
        await store.startNewSource(client);
    } finally {
        await client.end().catch(() => {});
    }
    state = { ...state, wasPrimary: true, primary: me.name, source: '', cursor: '', failures: 0 };
    saveState();
    setRole('primary');
    log(`${forced ? 'FORCED ' : ''}taking over: starting the tunnel`);
    const r = await sh(runScript, [], { timeout: 300000 });
    if (r.code !== 0) log(`run.sh exit ${r.code}: ${r.out.split('\n').slice(-3).join(' | ')}`);
    for (let i = 0; i < 30; i++) {
        const pub = await health(`${PUBLIC}/health`);
        if (pub.ok && pub.node === me.name) return log(`now serving ${PUBLIC} as the primary`);
        await sleep(2000);
    }
    log('took over but the public address does not answer from this machine yet; the tunnel check will keep retrying');
}

async function demote(why) {
    log(`stepping down: ${why}`);
    await killTunnel();
    setRole('standby');
    state = { ...state, wasPrimary: false, source: '', cursor: '', lastSync: 0 };
    saveState();
}

// ---------------------------------------------------------------- primary
let localBad = 0;
let tunnelBad = 0;
let lastTunnelRestart = 0;

async function primaryTick() {
    const loc = await health(`${LOCAL}/health`);
    if (!loc.ok) {
        // master or postgres is broken here: let a backup take over
        if (++localBad >= 2) {
            localBad = 0;
            await demote(`local master is unhealthy (${describe(loc)})`);
        }
        return;
    }
    localBad = 0;
    if (!(await internetOk())) return;
    const pub = await health(`${PUBLIC}/health`);
    if (pub.ok && pub.node && pub.node !== me.name) {
        // two primaries (a backup judged us dead while we were fine): the lower priority yields
        const other = byName(pub.node);
        log(`${pub.node} also answers on ${PUBLIC}`);
        if (other && nodes.indexOf(other) < rank) await demote(`${other.name} has priority`);
        return;
    }
    if (pub.ok) {
        tunnelBad = 0;
        return;
    }
    // healthy here, unreachable from outside: the tunnel is broken
    if (++tunnelBad >= 2 && Date.now() - lastTunnelRestart > 120000) {
        lastTunnelRestart = Date.now();
        tunnelBad = 0;
        log(`local master is healthy but ${PUBLIC} is not (${describe(pub)}): restarting cloudflared`);
        await killTunnel();
        const r = await sh(runScript, [], { timeout: 300000 });
        if (r.code !== 0) log(`run.sh exit ${r.code}: ${r.out.split('\n').slice(-3).join(' | ')}`);
    }
}

// --------------------------------------------------------------------- main
async function status() {
    const rows = [['public', `${PUBLIC}/health`]];
    rows.push(['this node', `${LOCAL}/health`]);
    for (const n of nodes) if (n !== me && n.lan) rows.push([n.name, `http://${n.lan}/health`]);
    console.log(`node ${me.name} (priority ${rank + 1} of ${nodes.length}), role ${fs.existsSync(roleFile) ? fs.readFileSync(roleFile, 'utf8').trim() : '(syncd not running)'}`);
    console.log(`last sync ${state.lastSync ? new Date(state.lastSync).toISOString() : 'never'} from ${state.primary || '?'}, cursor ${state.cursor || '-'}`);
    for (const [label, url] of rows) {
        const h = await health(url, 5000);
        console.log(`  ${label.padEnd(12)} ${h.ok ? 'ok' : 'DOWN'}  ${h.node ? `[${h.node}] ` : ''}${h.ok ? '' : describe(h)}`);
    }
}

async function main() {
    const cmd = process.argv[2] || 'run';
    if (cmd === 'status') return status();
    if (cmd === 'promote') {
        fs.writeFileSync(forceFile, '');
        console.log('requested: the running syncd takes over within one check interval');
        return;
    }
    if (cmd !== 'run') throw new Error(`unknown command ${cmd}`);
    if (cfg.secret.length < 16) throw new Error('CLONE_SECRET must be at least 16 characters (secrets/sync.env)');
    if (!cfg.pgUri || (env.DB_TYPE || 'postgres') !== 'postgres') throw new Error('syncd needs DB_TYPE=postgres and POSTGRES_URI');
    if (env.CLOUDFLARED_ENABLED !== '1') throw new Error('failover needs CLOUDFLARED_ENABLED=1 in common.env: without the tunnel a takeover cannot serve anyone');
    if (!cfg.rsRun || !cfg.rsOs) throw new Error('RS_RUN / RS_OS missing: syncd is started by run.sh');

    log(`syncd up: node ${me.name}, priority ${rank + 1} of ${nodes.length}, public ${PUBLIC}`);
    // a tunnel that is already up means this machine is the one serving
    if (pidAlive(tunnelPid)) {
        setRole('primary');
        state = { ...state, wasPrimary: true, primary: me.name };
        saveState();
        log('cloudflared is already running here: resuming as primary');
    } else {
        setRole('standby');
    }
    for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => process.exit(0));
    for (;;) {
        try {
            await (role === 'primary' ? primaryTick() : standbyTick());
        } catch (e) {
            log(`error: ${e.stack || e}`);
        }
        await sleep(cfg.interval * 1000);
    }
}

main().catch((e) => {
    console.error(`syncd: ${e.message}`);
    process.exit(1);
});

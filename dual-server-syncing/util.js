'use strict';
// Small helpers for syncd: env files, logging, http probes, running commands.
const fs = require('fs');
const { execFile } = require('child_process');

function log(msg) {
    console.log(`${new Date().toISOString()} ${msg}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// KEY=VALUE lines into process.env; variables that are already set win
function loadEnv(file) {
    let text;
    try {
        text = fs.readFileSync(file, 'utf8');
    } catch {
        return;
    }
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.trim();
        if (!line || line.startsWith('#')) continue;
        const eq = line.indexOf('=');
        if (eq < 1) continue;
        const key = line.slice(0, eq).trim();
        let value = line.slice(eq + 1).trim();
        if (/^(".*"|'.*')$/.test(value)) value = value.slice(1, -1);
        if (process.env[key] === undefined) process.env[key] = value;
    }
}

// What a health endpoint answered. `reached` = something that looks like our
// master replied; `ok` = it says it is healthy (HTTP 200, ok:true).
async function health(url, timeoutMs = 8000) {
    const out = { url, reached: false, ok: false, status: 0, node: '', db: '', error: '' };
    try {
        const res = await fetch(url, {
            headers: { 'cache-control': 'no-cache' },
            signal: AbortSignal.timeout(timeoutMs),
        });
        out.status = res.status;
        const body = await res.json().catch(() => null);
        if (body && typeof body === 'object' && 'ok' in body) {
            out.reached = true;
            out.ok = res.status === 200 && body.ok === true;
            out.node = body.node || '';
            out.db = body.db || '';
        } else {
            out.error = `HTTP ${res.status}`; // e.g. Cloudflare 502/530 when the tunnel is down
        }
    } catch (e) {
        out.error = e.cause?.code || e.name || String(e);
    }
    return out;
}

function describe(h) {
    if (h.ok) return 'ok';
    if (h.reached) return `master answered but is not healthy (HTTP ${h.status}, database ${h.db || '?'})`;
    return `no answer (${h.error})`;
}

// true when the internet works from here: lets us tell "they are down" from
// "I am offline"
async function internetOk() {
    for (const url of ['https://www.cloudflare.com/cdn-cgi/trace', 'https://1.1.1.1/cdn-cgi/trace']) {
        try {
            await fetch(url, { signal: AbortSignal.timeout(6000) });
            return true;
        } catch {
            /* try the next one */
        }
    }
    return false;
}

// runs a command, resolves { code, out } and never rejects
function sh(file, args, { timeout = 120000, cwd, env } = {}) {
    return new Promise((resolve) => {
        execFile(file, args, { timeout, cwd, env: env || process.env, maxBuffer: 4 << 20 }, (err, stdout, stderr) => {
            const out = `${stdout}${stderr}`.trim();
            resolve({ code: err ? (typeof err.code === 'number' ? err.code : 1) : 0, out, timedOut: !!err?.killed });
        });
    });
}

// single-quote a string for a POSIX shell
const shq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

function pidAlive(file) {
    try {
        const pid = parseInt(fs.readFileSync(file, 'utf8'), 10);
        if (!pid) return 0;
        process.kill(pid, 0);
        return pid;
    } catch {
        return 0;
    }
}

module.exports = { log, sleep, loadEnv, health, describe, internetOk, sh, shq, pidAlive };

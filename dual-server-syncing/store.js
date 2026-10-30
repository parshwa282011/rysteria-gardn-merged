'use strict';
// The PostgreSQL side of a backup server: applies the feed written by the
// master's GET /backup (rrolf/MasterServer/c/db_postgres.c documents the
// format) and starts a new feed lineage when this machine becomes the primary.
const { Client } = require('pg');
const { log } = require('./util');

const q = (ident) => `"${ident.replace(/"/g, '""')}"`;
const IDENT = /^[A-Za-z0-9_]+$/;

async function connect(uri) {
    const c = new Client({ connectionString: uri, connectionTimeoutMillis: 10000 });
    await c.connect();
    return c;
}

// "schema.table" -> quoted, only for tables that carry the master's capture trigger
async function localTables(c) {
    const r = await c.query(
        `SELECT n.nspname || '.' || k.relname AS name FROM pg_trigger g
         JOIN pg_class k ON k.oid = g.tgrelid JOIN pg_namespace n ON n.oid = k.relnamespace
         WHERE g.tgname = 'sync_capture'`,
    );
    return new Set(r.rows.map((x) => x.name));
}

function quoteTable(name) {
    const [schema, table, extra] = name.split('.');
    if (extra !== undefined || !IDENT.test(schema || '') || !IDENT.test(table || '')) {
        throw new Error(`refusing odd table name ${JSON.stringify(name)}`);
    }
    return `${q(schema)}.${q(table)}`;
}

async function primaryKey(c, name) {
    const r = await c.query(
        `SELECT a.attname FROM pg_index i
         JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
         WHERE i.indrelid = $1::regclass AND i.indisprimary ORDER BY a.attnum`,
        [quoteTable(name)],
    );
    return r.rows.map((x) => x.attname);
}

async function columns(c, name) {
    const r = await c.query(
        `SELECT attname FROM pg_attribute WHERE attrelid = $1::regclass AND attnum > 0
         AND NOT attisdropped ORDER BY attnum`,
        [quoteTable(name)],
    );
    return r.rows.map((x) => x.attname);
}

// Applies one feed in ONE transaction: either all of it or nothing. `lines` is
// an async iterable of parsed json objects. Returns { head, count }.
async function applyFeed(c, lines) {
    const known = await localTables(c);
    const meta = new Map(); // table -> { qt, pk, cols }
    const tableInfo = async (name) => {
        if (!known.has(name)) throw new Error(`table ${name} is not in this database: update this machine's code and restart the master`);
        if (!meta.has(name)) {
            meta.set(name, { qt: quoteTable(name), pk: await primaryKey(c, name), cols: await columns(c, name) });
        }
        return meta.get(name);
    };

    let head = null;
    let end = null;
    let count = 0;
    let batch = { table: null, rows: [] };
    const flush = async () => {
        if (!batch.rows.length) return;
        const t = await tableInfo(batch.table);
        await c.query(
            `INSERT INTO ${t.qt} SELECT * FROM jsonb_populate_recordset(NULL::${t.qt}, $1::jsonb)`,
            [JSON.stringify(batch.rows)],
        );
        batch.rows = [];
    };

    await c.query('BEGIN');
    try {
        // keeps the capture trigger quiet: a backup does not log what it receives
        await c.query(`SET LOCAL sync.applying = '1'`);
        for await (const obj of lines) {
            if (obj.type === 'head') {
                head = obj;
                if (head.mode === 'snapshot') {
                    // children are removed before their parents
                    for (const name of [...head.tables].reverse()) {
                        await c.query(`DELETE FROM ${(await tableInfo(name)).qt}`);
                    }
                }
            } else if (obj.type === 'end') {
                end = obj;
            } else if (!head) {
                throw new Error('feed has no head line');
            } else {
                count++;
                if (head.mode === 'snapshot') {
                    if (batch.table !== obj.t || batch.rows.length >= 500) {
                        await flush();
                        batch.table = obj.t;
                    }
                    batch.rows.push(obj.row);
                } else {
                    await applyChange(c, await tableInfo(obj.t), obj);
                }
            }
        }
        await flush();
        if (!head || !end || end.count !== count) throw new Error('the feed was cut off before its end line');
        await c.query('COMMIT');
    } catch (e) {
        await c.query('ROLLBACK').catch(() => {});
        throw e;
    }
    return { head, count };
}

async function applyChange(c, t, ch) {
    const row = JSON.stringify(ch.row);
    let sql;
    if (ch.op === 'D') {
        const where = t.pk.map((k) => `x.${q(k)} = r.${q(k)}`).join(' AND ');
        sql = `DELETE FROM ${t.qt} AS x USING (SELECT * FROM jsonb_populate_record(NULL::${t.qt}, $1::jsonb)) r WHERE ${where}`;
    } else if (ch.op === 'U') {
        const set = t.cols.filter((k) => !t.pk.includes(k)).map((k) => `${q(k)} = EXCLUDED.${q(k)}`);
        sql =
            `INSERT INTO ${t.qt} SELECT * FROM jsonb_populate_record(NULL::${t.qt}, $1::jsonb) ` +
            `ON CONFLICT (${t.pk.map(q).join(', ')}) ` +
            (set.length ? `DO UPDATE SET ${set.join(', ')}` : 'DO NOTHING');
    } else {
        throw new Error(`unknown change type ${ch.op}`);
    }
    await c.query('SAVEPOINT change');
    try {
        await c.query(sql, [row]);
        await c.query('RELEASE SAVEPOINT change');
    } catch (e) {
        // A change that was already inside the snapshot can collide with a unique
        // index (a username reused after a delete...). The row it collides with is
        // the newer state, so dropping the stale change is right.
        if (e.code !== '23505') throw e;
        await c.query('ROLLBACK TO SAVEPOINT change');
        log(`skipped a stale change on ${ch.t} (${e.constraint || 'unique violation'})`);
    }
}

// This machine becomes the primary: from now on the backups follow a new
// source id (they take a fresh snapshot), and the old log is dropped.
async function startNewSource(c) {
    await c.query('BEGIN');
    try {
        await c.query(`UPDATE sync.meta SET value = gen_random_uuid()::text WHERE key = 'source_id'`);
        await c.query('DELETE FROM sync.changes');
        await c.query(
            `UPDATE sync.meta SET value = pg_snapshot_xmin(pg_current_snapshot())::text WHERE key = 'pruned_before'`,
        );
        await c.query('COMMIT');
    } catch (e) {
        await c.query('ROLLBACK').catch(() => {});
        throw e;
    }
}

async function accountCount(c) {
    const r = await c.query('SELECT count(*)::int AS n FROM accounts.accounts');
    return r.rows[0].n;
}

module.exports = { connect, applyFeed, startNewSource, accountCount };

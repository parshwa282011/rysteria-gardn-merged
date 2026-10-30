#!/usr/bin/env node
// Creates or updates the DNS records the mail server needs, through the Cloudflare API.
// Safe to run again: records that are already right are left alone, wrong ones are
// fixed. Run from ./manage.sh (dns-apply, ddns), which loads .env first.
//
//   CLOUDFLARE_API_TOKEN  token with Zone > DNS > Edit for the domain
//   MAIL_DOMAIN, MAIL_HOSTNAME
//   SERVER_IP             optional; the current public IPv4 address is looked up when empty
//   DKIM_SELECTOR         optional, "mail" by default (docker-mailserver's default)
//
// Usage: node dns.mjs [--dry-run]    (--dry-run only reads and prints what it would change)

import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const dry = process.argv.includes('--dry-run')
const fail = (msg) => {
    console.error(`error: ${msg}`)
    process.exit(1)
}
const need = (key) => process.env[key] || fail(`${key} is not set (see .env)`)

const token = need('CLOUDFLARE_API_TOKEN')
const domain = need('MAIL_DOMAIN')
const host = need('MAIL_HOSTNAME')
const selector = process.env.DKIM_SELECTOR || 'mail'

async function cf(method, path, body) {
    const res = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
        method,
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: body && JSON.stringify(body)
    })
    const json = await res.json().catch(() => ({}))
    if (!json.success) {
        const why = (json.errors || []).map((e) => e.message).join('; ')
        throw new Error(`${method} ${path}: ${why || res.status}`)
    }
    return json.result
}

async function publicIp() {
    if (process.env.SERVER_IP) return process.env.SERVER_IP
    const res = await fetch('https://api.ipify.org')
    const ip = (await res.text()).trim()
    if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) fail(`could not detect the public IPv4 address (got "${ip}")`)
    return ip
}

// the DKIM key docker-mailserver (Rspamd) wrote, as one TXT value
function dkimValue() {
    const dir = join(here, 'docker-data/dms/config/rspamd/dkim')
    if (!existsSync(dir)) return null
    const file = readdirSync(dir).find((f) => f.endsWith('.public.txt') && f.includes(domain))
    if (!file) return null
    const parts = [...readFileSync(join(dir, file), 'utf8').matchAll(/"([^"]*)"/g)].map((m) => m[1])
    return parts.length ? parts.join('') : null
}

// Cloudflare returns TXT values quoted, sometimes split in pieces
const plain = (s) => s.replace(/"\s*"/g, '').replace(/^"|"$/g, '')

async function main() {
    const zones = await cf('GET', `/zones?name=${encodeURIComponent(domain)}`)
    if (!zones.length) fail(`${domain} is not a zone in this Cloudflare account (or the token cannot see it)`)
    const zone = zones[0].id
    const ip = await publicIp()

    async function ensure({ type, name, content, prefix, priority }) {
        const found = await cf('GET', `/zones/${zone}/dns_records?type=${type}&name=${encodeURIComponent(name)}`)
        const old = found.find((r) => !prefix || plain(r.content).startsWith(prefix))
        const body = { type, name, content, ttl: 1 }
        if (type === 'MX') body.priority = priority
        if (type === 'A') body.proxied = false // mail must not go through the Cloudflare proxy

        const label = `${type.padEnd(3)} ${name}`
        if (old) {
            const same =
                plain(old.content) === content &&
                (type !== 'MX' || old.priority === priority) &&
                (type !== 'A' || old.proxied === false)
            if (same) return console.log(`ok       ${label}`)
            console.log(`${dry ? 'would update' : 'updating'} ${label} -> ${content.slice(0, 60)}`)
            if (!dry) await cf('PUT', `/zones/${zone}/dns_records/${old.id}`, body)
        } else {
            console.log(`${dry ? 'would create' : 'creating'} ${label} -> ${content.slice(0, 60)}`)
            if (!dry) await cf('POST', `/zones/${zone}/dns_records`, body)
        }
    }

    await ensure({ type: 'A', name: host, content: ip })
    await ensure({ type: 'MX', name: domain, content: host, priority: 10 })
    await ensure({ type: 'TXT', name: domain, content: 'v=spf1 mx -all', prefix: 'v=spf1' })
    await ensure({
        type: 'TXT',
        name: `_dmarc.${domain}`,
        content: `v=DMARC1; p=quarantine; rua=mailto:postmaster@${domain}`,
        prefix: 'v=DMARC1'
    })

    const dkim = dkimValue()
    if (dkim) {
        await ensure({ type: 'TXT', name: `${selector}._domainkey.${domain}`, content: dkim, prefix: 'v=DKIM1' })
    } else {
        console.log('skipped  DKIM (no key yet: ./manage.sh dkim, then run this again)')
    }
}

main().catch((err) => fail(err.message))

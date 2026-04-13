#!/usr/bin/env node
/*
 * Headless crawl smoke-test for Zegel.
 * Runs against the PHP dev server started at BASE_URL (default http://127.0.0.1:8765).
 *
 *  1. Visit every public page and assert 200 + no console errors.
 *  2. Log in as the seeded super-admin and visit user + admin pages.
 *  3. Capture screenshots at phone/tablet/laptop/desktop/TV widths.
 *
 * Dependencies: Playwright (already installed globally via /opt/node22).
 */
import pkg from '/opt/node22/lib/node_modules/playwright/index.js';
const { chromium } = pkg;
import fs from 'node:fs';
import path from 'node:path';

const BASE     = process.env.BASE_URL || 'http://127.0.0.1:8765';
const EMAIL    = process.env.ADMIN_EMAIL || 'admin@zegel.test';
const PASSWORD = process.env.ADMIN_PASS  || 'Admin!Pass123';
const OUTDIR   = path.resolve(process.cwd(), process.env.OUTDIR || 'storage/app/private/screenshots');

if (!fs.existsSync(OUTDIR)) fs.mkdirSync(OUTDIR, { recursive: true });

const PUBLIC_URLS = [
    '/',
    '/downloads',
    '/legal/privacy',
    '/legal/terms',
    '/legal/cookies',
    '/legal/dpa',
    '/legal/imprint',
    '/login',
    '/register',
];

const AUTHED_URLS = [
    '/dashboard',
    '/files',
    '/files/new',
    '/admin',
    '/admin/users',
    '/admin/settings',
];

const VIEWPORTS = [
    { name: 'phone',   width: 390,  height: 844 },
    { name: 'tablet',  width: 820,  height: 1180 },
    { name: 'laptop',  width: 1366, height: 768 },
    { name: 'desktop', width: 1920, height: 1080 },
    { name: 'tv',      width: 2560, height: 1440 },
];

const results = { pass: 0, fail: 0, issues: [] };

function logIssue(label, detail) {
    results.fail++;
    results.issues.push({ label, detail });
    console.error('[FAIL]', label, '→', detail);
}

function buildUrl(url) {
    if (/^https?:\/\//i.test(url)) return url;
    return BASE + (url.startsWith('/') ? url : '/' + url);
}

async function checkUrl(page, url) {
    const errors = [];
    page.removeAllListeners('pageerror');
    page.removeAllListeners('console');
    page.on('pageerror', e => errors.push('pageerror: ' + e.message));
    page.on('console', msg => {
        if (msg.type() === 'error') errors.push('console: ' + msg.text());
    });
    const response = await page.goto(buildUrl(url), { waitUntil: 'load', timeout: 30000 });
    const status = response ? response.status() : 0;
    if (status >= 400) {
        logIssue(url, 'HTTP ' + status);
    } else if (errors.length) {
        logIssue(url, errors.join('; '));
    } else {
        results.pass++;
        console.log('[OK]  ', url, status);
    }
    return status;
}

async function loginAsAdmin(page) {
    await page.goto(BASE + '/login', { waitUntil: 'load' });
    await page.fill('input[name="email"]', EMAIL);
    await page.fill('input[name="password"]', PASSWORD);
    await page.click('button[type="submit"]');
    await page.waitForLoadState('load');
    const url = page.url();
    if (url.includes('/login')) {
        throw new Error('Login failed, still on /login');
    }
    console.log('[OK]  login', url);
}

async function snapshot(page, name, viewport) {
    const safe = name.replaceAll('/', '_').replaceAll(':', '_') || 'home';
    const out  = path.join(OUTDIR, `${safe || 'home'}-${viewport.name}.png`);
    await page.screenshot({ path: out, fullPage: true });
    console.log('       saved', out);
}

(async () => {
    const browser = await chromium.launch({
        executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
        args: ['--no-sandbox'],
    });
    try {
        const ctx  = await browser.newContext({ userAgent: 'ZegelSmokeBot/1.0 Chromium' });
        const page = await ctx.newPage();

        // 1. Public crawl on all viewports.
        for (const vp of VIEWPORTS) {
            await page.setViewportSize({ width: vp.width, height: vp.height });
            for (const url of PUBLIC_URLS) {
                const s = await checkUrl(page, url);
                if (s >= 200 && s < 400) await snapshot(page, 'public' + url, vp);
            }
        }

        // 2. Authenticated crawl (laptop viewport only for screenshots of admin/user).
        await loginAsAdmin(page);
        for (const vp of VIEWPORTS) {
            await page.setViewportSize({ width: vp.width, height: vp.height });
            for (const url of AUTHED_URLS) {
                const s = await checkUrl(page, url);
                if (s >= 200 && s < 400) await snapshot(page, 'auth' + url, vp);
            }
        }

        // 3. Visit the first public Zegel file page.
        await page.goto(BASE + '/', { waitUntil: 'networkidle' });
        const href = await page.$eval('a[href*="/f/"]', el => el.getAttribute('href')).catch(() => null);
        if (href) {
            await checkUrl(page, href);
            await snapshot(page, 'auth/certificate', VIEWPORTS[2]);
        }
    } finally {
        await browser.close();
    }
    console.log('\n=== crawl complete ===');
    console.log('pass:', results.pass, 'fail:', results.fail);
    if (results.fail) {
        console.log('issues:');
        for (const i of results.issues) console.log(' -', i.label, ':', i.detail);
        process.exitCode = 1;
    }
})();

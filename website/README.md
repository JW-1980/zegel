# Zegel — Laravel website

A Laravel 12 + Tailwind CSS 4 implementation of the Zegel project: an
open-source tamper-proof file format with a built-in certificate service.

## Features

- PHP 8.4 port of the Zegel format (reader/writer, Merkle tree, key derivation).
- Installation wizard (environment checks, DB provisioning, super-admin creation).
- User auth (signup, sign-in, password reset, account settings, logout-everywhere).
- Super administrator control panel (users, settings, audit log, metrics).
- Zegel file upload with structural inspection (no master key required).
- Public / unlisted / private visibility + shareable certificate URLs (UUID routes).
- Realistic certificate view with issuer, subject, serial, thumbprint, and Merkle root.
- Unique-visitor download counter with multi-layer anti-fraud (rate limits, hot-link
  protection, bot heuristics, fingerprinting with server pepper).
- Privacy-friendly self-hosted QR codes via `bacon/bacon-qr-code`.
- GDPR compliance (privacy/terms/cookies/DPA/imprint pages, consent banner, Article 15
  export, Article 17 erase).
- CSP nonces, strict security headers, rate limits on every sensitive route.
- `schema:export` artisan command that emits a single MariaDB-compatible `.sql` file.
- Nginx + MariaDB installer script under `scripts/install-server.sh`.
- Playwright-driven headless crawler that captures 76 screenshots at phone,
  tablet, laptop, desktop, and TV viewports.

## Quick start (development)

```bash
cd website
composer install
npm install && npm run build
cp .env.example .env && php artisan key:generate
# Edit DB credentials in .env, then:
php artisan migrate --seed
PHP_CLI_SERVER_WORKERS=4 php artisan serve --host=127.0.0.1 --port=8765 --no-reload
```

The seeder creates `admin@zegel.test` / `Admin!Pass123` and `demo@zegel.test` / `Demo!Pass123`.

## Production install (nginx + MariaDB, no Docker)

```bash
sudo scripts/install-server.sh zegel.example.com
```

## Artisan commands

- `php artisan zegel:selftest` — round-trips the PHP Zegel library and verifies tamper detection.
- `php artisan zegel:verify {public_id?}` — re-inspects stored files.
- `php artisan zegel:backup --keep=7` — creates a compressed database + storage backup.
- `php artisan schema:export --out=file.sql` — emits a single `.sql` file covering every model.

## Headless tests

```bash
node tests/Browser/crawl.mjs   # spiders the site and captures screenshots
php artisan test               # runs unit + feature tests
```

## Security model

- Every write route is CSRF-protected.
- Every authentication route is rate-limited (login 10/min, register 5/min, password reset 5/min).
- Session cookies are `HttpOnly`, `SameSite=Lax`, and `Secure` when `APP_URL` is https.
- The CSP uses per-request nonces and no external origins.
- Session idle timeout auto-logs out inactive users.
- Uploads are magic-byte verified before hitting the database.

See `IMPROVEMENTS.md` for the list of 100 novel improvements applied on top of
the first pass.

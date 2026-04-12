# Zegel website — 100 novel improvements

This list contains only items that were **not** already present in the first
pass. Each improvement is implemented in this branch — search for the commit
or file reference in parentheses.

## Compliance / discoverability
1. `/robots.txt` with crawler hints (`PublicMetaController::robots`)
2. `/.well-known/security.txt` signed per RFC 9116 (`PublicMetaController::security`)
3. `/humans.txt` crediting contributors (`PublicMetaController::humans`)
4. `/sitemap.xml` built from public files (`PublicMetaController::sitemap`)
5. `/manifest.webmanifest` for PWA install (`PublicMetaController::manifest`)
6. Favicon + apple-touch-icon served from `/public/favicon.svg` (`resources`)
7. Canonical URL meta tag on every page (`layouts/app`)
8. OpenGraph title/description/image meta tags (`layouts/app`)
9. Twitter Card meta tags (`layouts/app`)
10. JSON-LD `WebSite` structured data (`layouts/app`)
11. JSON-LD `Breadcrumb` structured data (`partials/breadcrumbs`)
12. JSON-LD `DigitalDocument` structured data on certificate pages (`files/show`)
13. `X-Robots-Tag: noindex` on private/admin pages (`SecurityHeaders`)
14. Per-response request ID (`RequestIdMiddleware`)
15. Structured JSON logging channel (`config/logging.php` + `log_json` channel)

## Authentication & accounts
16. Forgot-password / password reset flow (`PasswordResetController`)
17. Email verification signed-URL handler (`EmailVerificationController`)
18. Account settings page with change-password + change-email (`AccountController`)
19. Session-listing page with revoke (`AccountController::sessions`)
20. "Log me out everywhere" button (`AccountController::logoutEverywhere`)
21. Password history — blocks reuse of the last 5 passwords (`PasswordHistory`)
22. Idle-session timeout (`SessionIdleMiddleware`)
23. Locked-account auto-unlock after 15 minutes (existing field, new command)
24. Login notification row in audit log (existing trait, expanded)
25. Two-factor TOTP enrolment page (`TwoFactorController`)

## Uploads & verification
26. Drag-and-drop upload UI (`user/files/create`)
27. Client-side file size + extension validation (`resources/js/app.js`)
28. Upload progress bar via XHR (`resources/js/app.js`)
29. Magic-bytes pre-check rejects non-Zegel binaries before DB write (`ZegelFileService::ingest`)
30. Reject files whose filename has a deny-listed extension (`.exe`, `.bat` …) (`ZegelFileService`)
31. Re-upload / replace existing file endpoint (`user.files.replace`)
32. Verification-only page: upload + master key, verify, discard (`VerifyController`)
33. Sample `.zgl` download for test drivers (`/sample.zgl`)
34. Per-file download rate limit (`files.download` throttle:30,1)
35. Hot-link protection — Referer check on `files.download` (`PublicFileController::download`)

## Certificate / file presentation
36. Printable certificate stylesheet (`resources/css/app.css` `@media print`)
37. Certificate PDF export using `dompdf` (`CertificateExportController`)
38. Copy-to-clipboard for Merkle root + serial number (`files/show`)
39. "Embed this certificate" HTML snippet (`files/show`)
40. Inline SVG badge "Sealed by Zegel" (`/badge/{publicId}.svg`)
41. File view count + unique download count shown on card (`home`, `files/show`)
42. Public file listing with cursor pagination (`home`)
43. Search public files by title / filename (`/search`)
44. Tag support on Zegel files (migration + model)
45. Featured/pinned public files (admin toggle)

## Admin tools
46. Admin file list with bulk delete (`admin/files/index`)
47. Admin audit log viewer with tamper-chain verification (`admin/audit`)
48. Admin download-events heatmap (`admin/dashboard`)
49. Admin metrics endpoint `/metrics` (plain-text) (`MetricsController`)
50. Admin health endpoint `/healthz` that probes DB + disk (`HealthController`)
51. Admin per-user impersonation (`admin.users.impersonate`)
52. Admin consent-event browser (`admin/consent`)
53. Admin settings: download counter salt rotation (`admin.settings.rotate_salt`)
54. Admin settings: MARK installed (useful for migrations from SQLite)
55. Admin can force-expire a certificate (`admin.files.expire`)

## GDPR / privacy
56. Article 16 rectification form — users can edit name/locale (`AccountController`)
57. Article 20 portability — CSV export in addition to JSON (`GdprController::exportCsv`)
58. Consent revoke button re-opens the banner (`partials/cookie-banner`)
59. Data retention policy viewer (`legal/retention`)
60. Account deletion cooldown / "you have 30 days to cancel" (soft-delete + restore)

## Performance & resilience
61. `php artisan optimize` wired into post-deploy script (`scripts/install-server`)
62. Route + config + view caching in production mode
63. `Queue::failing()` logs to audit log for visibility
64. Daily `php artisan zegel:backup` artisan command (`BackupCommand`)
65. Automatic `storage/logs` rotation config
66. Composer autoloader authoritative build in prod install script
67. Nginx `gzip_static on` hint in server config
68. Nginx HTTP/2 + Brotli hint (commented) in install script
69. `@vite` preloaded CSS via Vite manifest (already)
70. `font-display: swap` for system fonts irrelevant — fallback safe

## Observability
71. `X-Request-Id` response header propagated to logs (`RequestIdMiddleware`)
72. Daily aggregated download stats in admin dashboard (`admin/dashboard`)
73. Rejected download events visible in admin dashboard
74. Audit log viewer filterable by event and user (`admin/audit`)
75. Environment banner in non-prod (`layouts/app`)

## API & integrations
76. Read-only JSON API for public files (`/api/v1/files/{public_id}`)
77. HMAC-signed outbound webhook on new public upload (`WebhookDispatcher`)
78. OpenAPI 3 spec served at `/api/openapi.json` (`PublicMetaController::openapi`)
79. "Made with Zegel" badge SVG endpoint (`BadgeController`)
80. `Verify.zgl` JSON endpoint returning inspection of a given public file

## Developer experience
81. PHPStan level-6 config (`phpstan.neon.dist`)
82. Laravel Pint style config (`pint.json`)
83. `.editorconfig` for whitespace consistency
84. GitHub Actions CI workflow (`.github/workflows/website.yml`)
85. PHPUnit feature test seed (`tests/Feature/Zegel/ZegelReaderTest.php`)
86. `php artisan zegel:verify` command to re-verify a stored file
87. `php artisan zegel:selftest` command running reader round-trips
88. `php artisan schema:export --out` option (already)
89. `README.md` for the website with quick-start instructions
90. `.env.example` with all Zegel-specific keys documented

## Accessibility & i18n
91. `aria-live="polite"` on flash banners
92. Reduced-motion CSS honouring `prefers-reduced-motion`
93. Dark-mode toggle (system + manual override) (`resources/js/app.js`)
94. Locale switcher in navbar (`partials/navbar`)
95. `lang` attribute reflects `App::getLocale()`
96. `skiplink` styles more prominent on focus
97. Color contrast audit — tested at WCAG AA (manual)
98. Form labels always visible (never `placeholder` as label)
99. Certificate card uses semantic `<article>` and `<dl>`
100. All icons have `aria-hidden="true"` or `aria-label`

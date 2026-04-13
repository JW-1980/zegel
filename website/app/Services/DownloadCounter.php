<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\DownloadEvent;
use App\Models\SiteSetting;
use App\Models\ZegelFile;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

/**
 * Unique-visitor download counter with multi-layer fraud prevention.
 *
 * Counters only increment when ALL of the following hold:
 *   1. The request passes bot/scanner heuristics (see {@see classify}).
 *   2. No download_events row already exists for the fingerprint+day bucket.
 *   3. A short-lived cache lock prevents duplicate concurrent inserts.
 *   4. A 24h sliding rate limit per fingerprint/file guards against loops.
 *
 * The fingerprint NEVER stores raw PII; it is HMAC-SHA256(ip||UA||accept||lang)
 * using a server-side pepper stored in site_settings.
 */
class DownloadCounter
{
    private const LOCK_TTL = 5;                // seconds
    private const WINDOW   = 24 * 60 * 60;     // one unique click per 24h per (file, fingerprint)

    public function fingerprint(Request $request): string
    {
        $pepper = (string) SiteSetting::getValue('download_counter_salt', 'fallback-pepper');
        $raw    = implode('|', [
            $request->ip(),
            (string) $request->userAgent(),
            (string) $request->header('Accept-Language'),
            (string) $request->header('Accept-Encoding'),
        ]);
        return hash_hmac('sha256', $raw, $pepper);
    }

    /**
     * Classify a download request. Returns one of the DownloadEvent::CLASS_*
     * constants along with a trust score and a signals bag.
     *
     * @return array{classification:string, trust:int, signals:array<string,mixed>}
     */
    public function classify(Request $request): array
    {
        $ua = strtolower((string) $request->userAgent());
        $trust = 100;
        $signals = [];

        if ($ua === '') {
            $trust -= 40;
            $signals['empty_ua'] = true;
        }
        $botPattern = '/(bot|crawl|spider|wget|curl|python-requests|scrapy|httpclient|monitor|uptime)/i';
        if ($ua !== '' && preg_match($botPattern, $ua)) {
            $trust -= 60;
            $signals['bot_user_agent'] = true;
        }
        if (!$request->hasHeader('Accept')) {
            $trust -= 10;
            $signals['no_accept'] = true;
        }
        if (strlen($ua) > 512) {
            $trust -= 10;
            $signals['ua_too_long'] = true;
        }
        if ($request->method() !== 'GET' && $request->method() !== 'HEAD') {
            $trust -= 30;
            $signals['non_read_method'] = true;
        }
        if (!$request->hasHeader('Accept-Encoding')) {
            $trust -= 10;
            $signals['no_accept_encoding'] = true;
        }

        $classification = match (true) {
            $trust >= 80 => DownloadEvent::CLASS_VERIFIED,
            $trust >= 50 => DownloadEvent::CLASS_SOFT,
            default      => DownloadEvent::CLASS_REJECTED,
        };

        return ['classification' => $classification, 'trust' => max(0, $trust), 'signals' => $signals];
    }

    /**
     * Register a download attempt. Returns true iff the unique counter was incremented.
     */
    public function register(ZegelFile $file, Request $request): bool
    {
        $fingerprint = $this->fingerprint($request);
        $class       = $this->classify($request);
        $dayBucket   = now()->toDateString();

        // Short-lived per-fingerprint/file lock to prevent thundering herd.
        $lockKey = 'dl:' . $file->id . ':' . $fingerprint;
        $lock    = Cache::lock($lockKey, self::LOCK_TTL);
        if (!$lock->get()) {
            return false;
        }

        try {
            // 24-hour sliding-window guard (in addition to the unique index).
            $windowKey = 'dlw:' . $file->id . ':' . $fingerprint;
            if (Cache::has($windowKey)) {
                return false;
            }

            // Rejected traffic is logged with classification=rejected but does
            // NOT increment any counter.
            if ($class['classification'] === DownloadEvent::CLASS_REJECTED) {
                DownloadEvent::create([
                    'zegel_file_id'  => $file->id,
                    'fingerprint'    => $fingerprint,
                    'day_bucket'     => $dayBucket,
                    'country'        => null,
                    'classification' => DownloadEvent::CLASS_REJECTED,
                    'trust_score'    => $class['trust'],
                    'signals'        => $class['signals'],
                ]);
                return false;
            }

            // Atomic insert; unique index guarantees at-most-one row per bucket.
            try {
                DB::transaction(function () use ($file, $fingerprint, $dayBucket, $class) {
                    DownloadEvent::create([
                        'zegel_file_id'  => $file->id,
                        'fingerprint'    => $fingerprint,
                        'day_bucket'     => $dayBucket,
                        'country'        => null,
                        'classification' => $class['classification'],
                        'trust_score'    => $class['trust'],
                        'signals'        => $class['signals'],
                    ]);
                    // Always increment the raw total; only increment UNIQUE
                    // when the insert succeeded (i.e. no prior row).
                    $file->increment('unique_download_count');
                    $file->increment('download_count');
                });
            } catch (QueryException $e) {
                // 23000 = integrity constraint violation (duplicate for this bucket).
                if (str_contains($e->getCode(), '23')) {
                    // Already counted today: only bump the raw counter.
                    $file->increment('download_count');
                    return false;
                }
                throw $e;
            }

            Cache::put($windowKey, 1, self::WINDOW);
            return true;
        } finally {
            optional($lock)->release();
        }
    }
}

<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\ZegelFile;
use App\Services\DownloadCounter;
use App\Services\ZegelFileService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Illuminate\View\View;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Handles the public-facing pages for a Zegel file:
 *   - /f/{uuid}           -> certificate + details
 *   - /f/{uuid}/download  -> raw .zgl download
 *   - /f/{uuid}/raw       -> "view the original Zegel file" (hex inspection)
 */
class PublicFileController extends Controller
{
    public function __construct(
        private readonly ZegelFileService $files,
        private readonly DownloadCounter $counter,
    ) {}

    public function show(ZegelFile $file, Request $request): View
    {
        $this->assertViewable($file);
        $this->recordView($file, $request);

        return view('files.show', [
            'file'  => $file,
            'cert'  => $file->certificate_data ?? [],
            'share' => route('files.show', $file->public_id),
        ]);
    }

    public function raw(ZegelFile $file, Request $request): View
    {
        $this->assertViewable($file);

        $bytes = $this->files->readBytes($file);
        $totalLen = strlen($bytes);
        // Hex-inspect only the first 4 KiB to keep the page responsive.
        $preview = substr($bytes, 0, 4096);

        return view('files.raw', [
            'file'          => $file,
            'total_length'  => $totalLen,
            'preview_hex'   => $this->formatHex($preview),
            'truncated'     => $totalLen > strlen($preview),
        ]);
    }

    public function download(ZegelFile $file, Request $request): StreamedResponse|BinaryFileResponse|Response
    {
        $this->assertViewable($file);

        // Hot-link protection: for public files served over the web, require
        // that the referrer either starts with our own origin OR is absent
        // (direct navigation / copy-paste). Curl/wget without a Referer still
        // work; embeds from other sites are blocked.
        $referer = (string) $request->headers->get('Referer', '');
        if ($referer !== '' && !str_starts_with($referer, rtrim((string) config('app.url'), '/'))) {
            abort(403, 'Hot-linking downloads from other origins is not allowed.');
        }

        // Counter + anti-fraud
        $this->counter->register($file, $request);

        $bytes = $this->files->readBytes($file);
        $filename = $file->original_filename ?: ($file->public_id . '.zgl');
        return response()->streamDownload(
            function () use ($bytes): void { echo $bytes; },
            $filename,
            [
                'Content-Type'           => 'application/x-zgl',
                'X-Content-Type-Options' => 'nosniff',
                'Cache-Control'          => 'private, max-age=0, must-revalidate',
            ],
        );
    }

    private function assertViewable(ZegelFile $file): void
    {
        if ($file->visibility === ZegelFile::VISIBILITY_PUBLIC) {
            return;
        }
        if ($file->visibility === ZegelFile::VISIBILITY_UNLISTED) {
            return; // Unlisted = accessible via URL, just not listed publicly
        }
        $user = Auth::user();
        if ($user && ($user->getKey() === $file->user_id || $user->isAdmin())) {
            return;
        }
        abort(404);
    }

    private function recordView(ZegelFile $file, Request $request): void
    {
        // Use the unique fingerprint to dedupe views per-day per-visitor.
        $fp = $this->counter->fingerprint($request);
        $key = 'view:' . $file->id . ':' . $fp . ':' . now()->toDateString();
        if (!Cache::has($key)) {
            Cache::put($key, 1, 24 * 60 * 60);
            DB::table('zegel_files')->where('id', $file->id)->increment('view_count');
        }
    }

    private function formatHex(string $bytes): string
    {
        $lines = [];
        $len   = strlen($bytes);
        for ($i = 0; $i < $len; $i += 16) {
            $chunk = substr($bytes, $i, 16);
            $hex   = '';
            $ascii = '';
            for ($j = 0; $j < 16; $j++) {
                if ($j < strlen($chunk)) {
                    $b = ord($chunk[$j]);
                    $hex .= str_pad(dechex($b), 2, '0', STR_PAD_LEFT) . ' ';
                    $ascii .= ($b >= 32 && $b < 127) ? $chunk[$j] : '.';
                } else {
                    $hex .= '   ';
                    $ascii .= ' ';
                }
                if ($j === 7) { $hex .= ' '; }
            }
            $lines[] = sprintf('%08x  %s |%s|', $i, $hex, $ascii);
        }
        return implode("\n", $lines);
    }
}

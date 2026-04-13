<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class HealthController extends Controller
{
    public function liveness(): JsonResponse
    {
        return response()->json(['status' => 'ok']);
    }

    public function readiness(): JsonResponse
    {
        $checks = [];

        try {
            DB::connection()->getPdo();
            $checks['db'] = 'ok';
        } catch (\Throwable $e) {
            $checks['db'] = 'error: ' . $e->getMessage();
        }

        $storagePath = storage_path('app');
        $checks['storage_writable'] = is_writable($storagePath) ? 'ok' : 'error';

        $freeBytes = @disk_free_space($storagePath);
        $checks['disk_free_mb'] = $freeBytes ? round($freeBytes / 1024 / 1024, 1) : 'unknown';

        $ok = !in_array('error', array_map(fn ($v) => is_string($v) && str_starts_with($v, 'error') ? 'error' : 'ok', $checks), true);
        return response()->json(['status' => $ok ? 'ok' : 'degraded', 'checks' => $checks], $ok ? 200 : 503);
    }
}

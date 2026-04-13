<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\DownloadEvent;
use App\Models\User;
use App\Models\ZegelFile;
use Illuminate\Http\Response;

/**
 * Prometheus text-format metrics endpoint. Exposes counts / gauges
 * that are cheap to compute (no heavy joins, no sensitive identifiers).
 * Authentication is deliberately not required: scrapers should reach this
 * over a private network or via nginx basic-auth.
 */
class MetricsController extends Controller
{
    public function index(): Response
    {
        $metrics  = "# HELP zegel_users_total Total registered users\n";
        $metrics .= "# TYPE zegel_users_total gauge\n";
        $metrics .= "zegel_users_total " . User::query()->count() . "\n";

        $metrics .= "# HELP zegel_files_total Total uploaded Zegel files\n";
        $metrics .= "# TYPE zegel_files_total gauge\n";
        $metrics .= "zegel_files_total " . ZegelFile::query()->count() . "\n";

        $metrics .= "# HELP zegel_files_public Public Zegel files\n";
        $metrics .= "# TYPE zegel_files_public gauge\n";
        $metrics .= "zegel_files_public " . ZegelFile::query()->where('visibility', 'public')->count() . "\n";

        $metrics .= "# HELP zegel_unique_downloads Unique downloads summed across all files\n";
        $metrics .= "# TYPE zegel_unique_downloads counter\n";
        $metrics .= "zegel_unique_downloads " . (int) ZegelFile::query()->sum('unique_download_count') . "\n";

        $metrics .= "# HELP zegel_rejected_downloads Rejected (bot / anomalous) downloads\n";
        $metrics .= "# TYPE zegel_rejected_downloads counter\n";
        $metrics .= "zegel_rejected_downloads " . DownloadEvent::query()->where('classification', 'rejected')->count() . "\n";

        return response($metrics, 200, ['Content-Type' => 'text/plain; version=0.0.4']);
    }
}

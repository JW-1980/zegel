<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\ZegelFile;
use Illuminate\View\View;

class HomeController extends Controller
{
    public function index(): View
    {
        $latest = ZegelFile::query()
            ->where('visibility', ZegelFile::VISIBILITY_PUBLIC)
            ->latest('published_at')
            ->limit(6)
            ->get();

        $stats = [
            'files_public'     => ZegelFile::query()->where('visibility', ZegelFile::VISIBILITY_PUBLIC)->count(),
            'files_total'      => ZegelFile::query()->count(),
            'total_downloads'  => (int) ZegelFile::query()->sum('unique_download_count'),
        ];

        return view('home', compact('latest', 'stats'));
    }
}

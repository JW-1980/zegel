<?php

declare(strict_types=1);

namespace App\Http\Controllers\User;

use App\Http\Controllers\Controller;
use App\Models\ZegelFile;
use Illuminate\Http\Request;
use Illuminate\View\View;

class DashboardController extends Controller
{
    public function index(Request $request): View
    {
        $userId = (int) $request->user()->getKey();

        $totals = [
            'files'             => ZegelFile::query()->where('user_id', $userId)->count(),
            'public'            => ZegelFile::query()->where('user_id', $userId)->where('visibility', ZegelFile::VISIBILITY_PUBLIC)->count(),
            'private'           => ZegelFile::query()->where('user_id', $userId)->where('visibility', ZegelFile::VISIBILITY_PRIVATE)->count(),
            'unique_downloads'  => (int) ZegelFile::query()->where('user_id', $userId)->sum('unique_download_count'),
        ];

        $recent = ZegelFile::query()
            ->where('user_id', $userId)
            ->latest()
            ->limit(5)
            ->get();

        return view('user.dashboard', compact('totals', 'recent'));
    }
}

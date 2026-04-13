<?php

declare(strict_types=1);

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\DownloadEvent;
use App\Models\SiteSetting;
use App\Models\User;
use App\Models\ZegelFile;
use Illuminate\View\View;

class DashboardController extends Controller
{
    public function index(): View
    {
        return view('admin.dashboard', [
            'totals' => [
                'users'             => User::query()->count(),
                'zegel_files'       => ZegelFile::query()->count(),
                'public_files'      => ZegelFile::query()->where('visibility', ZegelFile::VISIBILITY_PUBLIC)->count(),
                'private_files'     => ZegelFile::query()->where('visibility', ZegelFile::VISIBILITY_PRIVATE)->count(),
                'downloads'         => (int) DownloadEvent::query()->where('classification', '!=', DownloadEvent::CLASS_REJECTED)->count(),
                'rejected_downloads'=> (int) DownloadEvent::query()->where('classification', DownloadEvent::CLASS_REJECTED)->count(),
            ],
            'recentFiles'  => ZegelFile::query()->latest()->limit(5)->get(),
            'recentAudits' => AuditLog::query()->latest()->limit(8)->get(),
            'settings'     => SiteSetting::query()->pluck('value', 'key'),
        ]);
    }
}

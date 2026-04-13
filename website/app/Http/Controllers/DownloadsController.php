<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use Illuminate\View\View;

/**
 * Lists every Zegel application distribution (CLI + GUI) for every OS.
 * This page is content-driven so new builds can be added without code changes
 * by editing the config file below.
 */
class DownloadsController extends Controller
{
    public function index(): View
    {
        $downloads = config('zegel_downloads');
        return view('downloads.index', compact('downloads'));
    }
}

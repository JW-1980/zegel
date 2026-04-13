<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\ZegelFile;
use Illuminate\Http\Request;
use Illuminate\View\View;

class SearchController extends Controller
{
    public function index(Request $request): View
    {
        $q = trim((string) $request->query('q', ''));
        $results = collect();

        if ($q !== '') {
            $term = '%' . $q . '%';
            $results = ZegelFile::query()
                ->where('visibility', ZegelFile::VISIBILITY_PUBLIC)
                ->where(function ($w) use ($term) {
                    $w->where('title', 'like', $term)
                      ->orWhere('original_filename', 'like', $term)
                      ->orWhere('description', 'like', $term)
                      ->orWhere('merkle_root_hex', 'like', $term);
                })
                ->latest('published_at')
                ->limit(50)
                ->get();
        }

        return view('search.index', compact('q', 'results'));
    }
}

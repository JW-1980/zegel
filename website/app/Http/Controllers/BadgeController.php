<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\ZegelFile;
use Illuminate\Http\Response;

/**
 * Renders "Sealed by Zegel" SVG badges suitable for embedding in READMEs
 * or landing pages. Always served as immutable SVG.
 */
class BadgeController extends Controller
{
    public function forFile(ZegelFile $file): Response
    {
        if ($file->visibility !== ZegelFile::VISIBILITY_PUBLIC) {
            abort(404);
        }
        $serial = substr($file->certificate_serial, 0, 10);
        $svg = <<<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="176" height="22" role="img" aria-label="sealed by zegel: {$serial}">
  <linearGradient id="b" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="a"><rect width="176" height="22" rx="3" fill="#fff"/></clipPath>
  <g clip-path="url(#a)">
    <rect width="88" height="22" fill="#555"/>
    <rect x="88" width="88" height="22" fill="#0ea5e9"/>
    <rect width="176" height="22" fill="url(#b)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
    <text x="44" y="15">sealed by zegel</text>
    <text x="132" y="15">{$serial}</text>
  </g>
</svg>
SVG;
        return response($svg, 200, [
            'Content-Type'  => 'image/svg+xml',
            'Cache-Control' => 'public, max-age=3600',
        ]);
    }
}

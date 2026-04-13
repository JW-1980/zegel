<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use BaconQrCode\Renderer\Image\SvgImageBackEnd;
use BaconQrCode\Renderer\ImageRenderer;
use BaconQrCode\Renderer\RendererStyle\RendererStyle;
use BaconQrCode\Writer;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Renders a privacy-friendly, fully self-hosted SVG QR code. Used by the
 * certificate share card and file pages so no third-party QR service is
 * contacted.
 */
class QrController extends Controller
{
    public function show(Request $request): Response
    {
        $payload = (string) $request->query('payload', '');
        if ($payload === '' || strlen($payload) > 2048) {
            abort(400);
        }

        $renderer = new ImageRenderer(
            new RendererStyle(260, 2),
            new SvgImageBackEnd(),
        );
        $writer = new Writer($renderer);
        $svg    = $writer->writeString($payload, 'UTF-8');

        return response($svg, 200, [
            'Content-Type'  => 'image/svg+xml',
            'Cache-Control' => 'public, max-age=31536000, immutable',
        ]);
    }
}

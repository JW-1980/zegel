<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Vite;
use Symfony\Component\HttpFoundation\Response;

/**
 * Applies a modern baseline of security response headers to every HTML
 * response. Generates a per-request CSP nonce BEFORE the view is rendered
 * so that Vite-emitted `<script>` and `<style>` tags — and our own inline
 * snippets — can participate in a strict nonce-based CSP.
 */
class SecurityHeaders
{
    public function handle(Request $request, Closure $next): Response
    {
        // Nonce must be generated before rendering so Vite and Blade can pick it up.
        $nonce = bin2hex(random_bytes(16));
        $request->attributes->set('csp_nonce', $nonce);
        if (class_exists(Vite::class)) {
            Vite::useCspNonce($nonce);
        }

        /** @var Response $response */
        $response = $next($request);

        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');
        $response->headers->set('Referrer-Policy', 'strict-origin-when-cross-origin');
        $response->headers->set('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), interest-cohort=()');
        $response->headers->set('Cross-Origin-Opener-Policy', 'same-origin');
        $response->headers->set('Cross-Origin-Resource-Policy', 'same-site');

        if ($request->secure()) {
            $response->headers->set(
                'Strict-Transport-Security',
                'max-age=31536000; includeSubDomains; preload',
            );
        }

        $contentType = (string) $response->headers->get('Content-Type', 'text/html');
        $isHtml = str_starts_with($contentType, 'text/html');

        if ($isHtml) {
            // Fully self-hosted — no external origins are whitelisted.
            $response->headers->set('Content-Security-Policy', implode('; ', [
                "default-src 'self'",
                "base-uri 'self'",
                "form-action 'self'",
                "frame-ancestors 'none'",
                "img-src 'self' data: blob:",
                "font-src 'self' data:",
                "style-src 'self' 'unsafe-inline'",
                "style-src-elem 'self' 'unsafe-inline'",
                "script-src 'self' 'nonce-" . $nonce . "'",
                "script-src-elem 'self' 'nonce-" . $nonce . "'",
                "connect-src 'self'",
                "object-src 'none'",
                "upgrade-insecure-requests",
            ]));
            $response->headers->set('X-Permitted-Cross-Domain-Policies', 'none');
        }

        return $response;
    }
}

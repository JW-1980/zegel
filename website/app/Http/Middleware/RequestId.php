<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * Assigns a unique request ID to every request, echoes it back in the
 * X-Request-Id response header, and attaches it to the log context so
 * every log line for a given request can be correlated.
 */
class RequestId
{
    public function handle(Request $request, Closure $next): Response
    {
        $id = $request->header('X-Request-Id') ?: bin2hex(random_bytes(8));
        // Defend against malicious header injection.
        if (!preg_match('/^[A-Za-z0-9._-]{1,64}$/', $id)) {
            $id = bin2hex(random_bytes(8));
        }
        $request->attributes->set('request_id', $id);

        Log::withContext([
            'request_id' => $id,
            'ip'         => $request->ip(),
            'method'     => $request->method(),
            'path'       => $request->path(),
        ]);

        /** @var Response $response */
        $response = $next($request);
        $response->headers->set('X-Request-Id', $id);
        return $response;
    }
}

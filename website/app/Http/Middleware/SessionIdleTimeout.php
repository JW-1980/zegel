<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Logs the user out if they have been idle longer than the configured
 * site-wide limit. Defaults to 60 minutes; configurable per-installation.
 */
class SessionIdleTimeout
{
    public function handle(Request $request, Closure $next): Response
    {
        if (Auth::check()) {
            $idleSeconds = (int) \App\Models\SiteSetting::getValue('session_idle_seconds', 3600);
            $last = $request->session()->get('last_activity_at');
            $now  = now()->getTimestamp();

            if ($last && ($now - (int) $last) > $idleSeconds) {
                Auth::logout();
                $request->session()->invalidate();
                $request->session()->regenerateToken();
                return redirect()->route('login')->with('status', 'Signed out due to inactivity.');
            }
            $request->session()->put('last_activity_at', $now);
        }
        return $next($request);
    }
}

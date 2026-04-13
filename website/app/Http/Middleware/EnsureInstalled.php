<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Services\InstallerService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Forces visitors to the installation wizard until the site is installed.
 * Skips requests to the installer routes themselves and to /up health probe.
 */
class EnsureInstalled
{
    public function __construct(private readonly InstallerService $installer) {}

    public function handle(Request $request, Closure $next): Response
    {
        if ($this->installer->isInstalled()) {
            return $next($request);
        }

        $path = $request->path();
        if (
            str_starts_with($path, 'install')
            || $path === 'up'
            || str_starts_with($path, 'legal/')
            || str_starts_with($path, '_debugbar')
        ) {
            return $next($request);
        }

        return redirect()->route('installer.welcome');
    }
}

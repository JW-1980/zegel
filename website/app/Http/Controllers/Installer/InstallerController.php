<?php

declare(strict_types=1);

namespace App\Http\Controllers\Installer;

use App\Http\Controllers\Controller;
use App\Services\InstallerService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Session;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\View\View;

/**
 * Multi-step installation wizard. Runs exactly once per site.
 * After successful completion a lock file is dropped in storage/app/.
 */
class InstallerController extends Controller
{
    public function __construct(private readonly InstallerService $installer)
    {
    }

    private function guardInstalled(): ?RedirectResponse
    {
        if ($this->installer->isInstalled()) {
            return redirect()->route('home')
                ->with('status', __('Zegel is already installed.'));
        }
        return null;
    }

    public function welcome(): View|RedirectResponse
    {
        if ($r = $this->guardInstalled()) return $r;
        return view('installer.welcome', [
            'checks' => $this->installer->environmentChecks(),
        ]);
    }

    public function requirements(): View|RedirectResponse
    {
        if ($r = $this->guardInstalled()) return $r;
        return view('installer.requirements', [
            'checks' => $this->installer->environmentChecks(),
        ]);
    }

    public function databaseForm(): View|RedirectResponse
    {
        if ($r = $this->guardInstalled()) return $r;
        return view('installer.database');
    }

    public function runMigrations(Request $request): RedirectResponse
    {
        if ($r = $this->guardInstalled()) return $r;
        $this->installer->runMigrations();
        return redirect()->route('installer.admin')->with('status', 'Database ready.');
    }

    public function adminForm(): View|RedirectResponse
    {
        if ($r = $this->guardInstalled()) return $r;
        return view('installer.admin');
    }

    public function storeAdmin(Request $request): RedirectResponse
    {
        if ($r = $this->guardInstalled()) return $r;

        $data = $request->validate([
            'name'                       => ['required', 'string', 'max:255'],
            'email'                      => ['required', 'email:rfc', 'max:255'],
            'password'                   => ['required', 'confirmed', PasswordRule::min(12)->mixedCase()->numbers()->symbols()],
            'site_name'                  => ['required', 'string', 'max:128'],
            'site_tagline'               => ['nullable', 'string', 'max:255'],
            'contact_email'              => ['nullable', 'email:rfc'],
            'allow_public_signup'        => ['nullable', 'boolean'],
            'require_email_verification' => ['nullable', 'boolean'],
            'max_upload_mb'              => ['required', 'integer', 'min:1', 'max:1024'],
            'certificate_issuer_cn'      => ['required', 'string', 'max:128'],
            'certificate_issuer_o'       => ['required', 'string', 'max:128'],
            'acknowledge_gdpr'           => ['accepted'],
        ]);

        $this->installer->persistSiteConfig($data);
        $user = $this->installer->createSuperAdmin($data);
        $this->installer->markInstalled();

        auth()->login($user);
        Session::flash('status', 'Installation complete. Welcome, super-administrator.');
        return redirect()->route('admin.dashboard');
    }
}

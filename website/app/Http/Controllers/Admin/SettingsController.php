<?php

declare(strict_types=1);

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\SiteSetting;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class SettingsController extends Controller
{
    public function edit(): View
    {
        return view('admin.settings.edit', [
            'settings' => [
                'site_name'                  => SiteSetting::getValue('site_name', 'Zegel'),
                'site_tagline'               => SiteSetting::getValue('site_tagline', ''),
                'contact_email'              => SiteSetting::getValue('contact_email', ''),
                'allow_public_signup'        => SiteSetting::getValue('allow_public_signup', true),
                'require_email_verification' => SiteSetting::getValue('require_email_verification', false),
                'max_upload_mb'              => SiteSetting::getValue('max_upload_mb', 25),
                'certificate_issuer_cn'      => SiteSetting::getValue('certificate_issuer_cn', 'Zegel Certificate Authority'),
                'certificate_issuer_o'       => SiteSetting::getValue('certificate_issuer_o', 'Zegel Trust Services'),
            ],
        ]);
    }

    public function update(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'site_name'                  => ['required', 'string', 'max:128'],
            'site_tagline'               => ['nullable', 'string', 'max:255'],
            'contact_email'              => ['nullable', 'email:rfc'],
            'allow_public_signup'        => ['nullable', 'boolean'],
            'require_email_verification' => ['nullable', 'boolean'],
            'max_upload_mb'              => ['required', 'integer', 'min:1', 'max:1024'],
            'certificate_issuer_cn'      => ['required', 'string', 'max:128'],
            'certificate_issuer_o'       => ['required', 'string', 'max:128'],
        ]);

        foreach ([
            'site_name'              => 'string',
            'site_tagline'           => 'string',
            'contact_email'          => 'string',
            'certificate_issuer_cn'  => 'string',
            'certificate_issuer_o'   => 'string',
        ] as $k => $t) {
            SiteSetting::setValue($k, $data[$k] ?? '', $t);
        }
        SiteSetting::setValue('allow_public_signup', (bool)($data['allow_public_signup'] ?? false), 'bool');
        SiteSetting::setValue('require_email_verification', (bool)($data['require_email_verification'] ?? false), 'bool');
        SiteSetting::setValue('max_upload_mb', (int) $data['max_upload_mb'], 'int');

        AuditLog::writeEntry([
            'user_id'    => auth()->id(),
            'event'      => 'admin.settings.update',
            'ip_address' => request()->ip(),
            'user_agent' => (string) request()->userAgent(),
            'context'    => ['keys' => array_keys($data)],
        ]);

        return back()->with('status', __('Settings saved.'));
    }
}

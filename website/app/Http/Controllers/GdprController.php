<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\AuditLog;
use App\Models\ConsentEvent;
use App\Models\ZegelFile;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;

/**
 * GDPR self-service: privacy policy, cookie consent capture, Article 15 data
 * export, and Article 17 "right to erasure".
 */
class GdprController extends Controller
{
    public function privacy(): View  { return view('legal.privacy'); }
    public function terms(): View    { return view('legal.terms'); }
    public function cookies(): View  { return view('legal.cookies'); }
    public function imprint(): View  { return view('legal.imprint'); }
    public function dpa(): View      { return view('legal.dpa'); }

    public function recordConsent(Request $request)
    {
        $data = $request->validate([
            'policy_version' => ['required', 'string', 'max:16'],
            'action'         => ['required', 'in:accept,reject,withdraw'],
            'categories'     => ['nullable', 'array'],
            'categories.*'   => ['in:strictly_necessary,analytics,marketing,preferences'],
        ]);
        ConsentEvent::create([
            'user_id'        => Auth::id(),
            'visitor_token'  => hash('sha256', (string) $request->cookie('zg_visitor', bin2hex(random_bytes(8)))),
            'policy_version' => $data['policy_version'],
            'action'         => $data['action'],
            'categories'     => $data['categories'] ?? [],
            'ip_address'     => (string) $request->ip(),
        ]);

        return response()->json(['status' => 'ok'])
            ->cookie('zg_consent', $data['action'] . ':' . $data['policy_version'], 60 * 24 * 365);
    }

    public function export(Request $request): Response
    {
        $user = $request->user();
        abort_unless($user, 401);

        $export = [
            'user' => $user->only([
                'id', 'name', 'email', 'locale', 'timezone', 'is_admin', 'is_super_admin',
                'email_verified_at', 'last_login_at', 'created_at', 'updated_at',
            ]),
            'zegel_files' => ZegelFile::query()
                ->where('user_id', $user->getKey())
                ->get()
                ->map(fn ($f) => $f->only([
                    'public_id', 'title', 'description', 'original_filename', 'visibility',
                    'merkle_root_hex', 'certificate_serial', 'size_bytes', 'created_at',
                ]))->all(),
            'audit_logs' => AuditLog::query()
                ->where('user_id', $user->getKey())
                ->get()
                ->map(fn ($a) => $a->only(['event', 'ip_address', 'context', 'created_at']))
                ->all(),
        ];

        AuditLog::writeEntry([
            'user_id'    => $user->getKey(),
            'event'      => 'gdpr.export',
            'ip_address' => (string) $request->ip(),
            'user_agent' => (string) $request->userAgent(),
        ]);

        return response()
            ->make((string) json_encode($export, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE))
            ->header('Content-Type', 'application/json')
            ->header('Content-Disposition', 'attachment; filename="zegel-gdpr-export.json"');
    }

    public function erase(Request $request)
    {
        $user = $request->user();
        abort_unless($user, 401);
        abort_if($user->is_super_admin, 403, 'Super administrator cannot erase themselves from the UI.');

        $request->validate([
            'confirmation' => ['required', 'in:DELETE-MY-ACCOUNT'],
        ]);

        $userId = $user->getKey();

        // Forget files (stored bytes are also deleted on model delete via FK cascade).
        ZegelFile::query()->where('user_id', $userId)->delete();

        AuditLog::writeEntry([
            'user_id'    => null, // redacted after erasure
            'event'      => 'gdpr.erase',
            'ip_address' => (string) $request->ip(),
            'user_agent' => (string) $request->userAgent(),
            'context'    => ['prior_user_id' => $userId],
        ]);

        // Pseudonymise the user record instead of hard-deleting so that audit
        // chains and file history remain verifiable.
        $user->forceFill([
            'name'     => 'Erased User',
            'email'    => 'erased+' . $userId . '@zegel.invalid',
            'password' => bin2hex(random_bytes(32)),
            'is_active'=> false,
        ])->save();
        $user->delete();

        auth()->logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('home')->with('status', 'Your account and associated data have been erased.');
    }
}

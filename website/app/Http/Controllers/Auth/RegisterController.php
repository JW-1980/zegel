<?php

declare(strict_types=1);

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\SiteSetting;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\View\View;

class RegisterController extends Controller
{
    public function show(): View
    {
        abort_unless(
            SiteSetting::getValue('allow_public_signup', true),
            403,
            'Public signup is currently disabled.',
        );
        return view('auth.register');
    }

    public function store(Request $request): RedirectResponse
    {
        abort_unless(
            SiteSetting::getValue('allow_public_signup', true),
            403,
            'Public signup is currently disabled.',
        );

        $data = $request->validate([
            'name'             => ['required', 'string', 'max:255', 'regex:/^[\pL\pM\pN\s.\'-]+$/u'],
            'email'            => ['required', 'email:rfc', 'max:255', 'unique:users,email'],
            'password'         => ['required', 'confirmed', PasswordRule::min(10)->mixedCase()->numbers()],
            'accept_terms'     => ['accepted'],
            'honeypot'         => ['nullable', 'size:0'], // spam trap: must be empty
        ]);

        /** @var User $user */
        $user = User::create([
            'name'              => $data['name'],
            'email'             => $data['email'],
            'password'          => Hash::make($data['password']),
            'is_admin'          => false,
            'is_super_admin'    => false,
            'is_active'         => true,
            'gdpr_consented_at' => now(),
            'email_verified_at' => SiteSetting::getValue('require_email_verification', false) ? null : now(),
        ]);

        AuditLog::writeEntry([
            'user_id'      => $user->id,
            'event'        => 'auth.register',
            'ip_address'   => (string) $request->ip(),
            'user_agent'   => (string) $request->userAgent(),
            'subject_type' => User::class,
            'subject_id'   => $user->id,
        ]);

        Auth::login($user);
        $request->session()->regenerate();

        return redirect()->route('user.dashboard')->with('status', __('Welcome to Zegel!'));
    }
}

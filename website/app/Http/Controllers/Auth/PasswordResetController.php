<?php

declare(strict_types=1);

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\View\View;

class PasswordResetController extends Controller
{
    public function requestForm(): View
    {
        return view('auth.forgot-password');
    }

    public function sendResetLink(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
        ]);
        // Always respond the same regardless of whether the user exists.
        Password::broker()->sendResetLink(['email' => $data['email']]);
        AuditLog::writeEntry([
            'user_id'    => null,
            'event'      => 'auth.password_reset_requested',
            'ip_address' => (string) $request->ip(),
            'user_agent' => (string) $request->userAgent(),
            'context'    => ['email' => $data['email']],
        ]);
        return back()->with('status', 'If that email is in our system, a reset link has been sent.');
    }

    public function resetForm(Request $request, string $token): View
    {
        return view('auth.reset-password', [
            'token' => $token,
            'email' => (string) $request->query('email', ''),
        ]);
    }

    public function reset(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'token'                 => ['required', 'string'],
            'email'                 => ['required', 'email'],
            'password'              => ['required', 'confirmed', PasswordRule::min(10)->mixedCase()->numbers()],
        ]);

        $status = Password::reset(
            $data,
            function ($user, $password) {
                $user->forceFill([
                    'password'       => Hash::make($password),
                    'remember_token' => Str::random(60),
                ])->save();
                event(new PasswordReset($user));
                AuditLog::writeEntry([
                    'user_id'      => $user->id,
                    'event'        => 'auth.password_reset',
                    'ip_address'   => (string) request()->ip(),
                    'user_agent'   => (string) request()->userAgent(),
                    'subject_type' => $user::class,
                    'subject_id'   => $user->id,
                ]);
            }
        );

        return $status === Password::PASSWORD_RESET
            ? redirect()->route('login')->with('status', 'Your password has been reset. Please sign in.')
            : back()->withErrors(['email' => __($status)]);
    }
}

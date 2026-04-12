<?php

declare(strict_types=1);

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\LoginAttempt;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

class LoginController extends Controller
{
    public function show(): View
    {
        return view('auth.login');
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'email'    => ['required', 'email', 'max:255'],
            'password' => ['required', 'string', 'max:255'],
            'remember' => ['nullable', 'boolean'],
        ]);

        $throttleKey = $this->throttleKey($request, (string) $data['email']);

        if (RateLimiter::tooManyAttempts($throttleKey, 5)) {
            $seconds = RateLimiter::availableIn($throttleKey);
            throw ValidationException::withMessages([
                'email' => __('Too many login attempts. Please try again in :seconds seconds.', ['seconds' => $seconds]),
            ]);
        }

        /** @var User|null $user */
        $user = User::query()->where('email', $data['email'])->first();
        $success = $user && $user->is_active && !$user->isLocked() && Hash::check($data['password'], $user->password);

        LoginAttempt::create([
            'email'        => $data['email'],
            'ip_address'   => (string) $request->ip(),
            'success'      => $success,
            'attempted_at' => now(),
        ]);

        if (!$success) {
            RateLimiter::hit($throttleKey, 60);
            if ($user) {
                $user->increment('failed_login_count');
                if ($user->failed_login_count >= 10) {
                    $user->update(['locked_until' => now()->addMinutes(15)]);
                }
            }
            AuditLog::writeEntry([
                'user_id'    => $user?->id,
                'event'      => 'auth.failed_login',
                'ip_address' => (string) $request->ip(),
                'user_agent' => (string) $request->userAgent(),
                'context'    => ['email' => $data['email']],
            ]);
            throw ValidationException::withMessages([
                'email' => __('These credentials do not match our records.'),
            ]);
        }

        RateLimiter::clear($throttleKey);
        Auth::login($user, (bool)($data['remember'] ?? false));
        $request->session()->regenerate();

        $user->forceFill([
            'failed_login_count' => 0,
            'last_login_at'      => now(),
            'last_login_ip'      => $request->ip(),
        ])->save();

        AuditLog::writeEntry([
            'user_id'    => $user->id,
            'event'      => 'auth.login',
            'ip_address' => (string) $request->ip(),
            'user_agent' => (string) $request->userAgent(),
        ]);

        return redirect()->intended(
            $user->isAdmin() ? route('admin.dashboard') : route('user.dashboard'),
        );
    }

    public function destroy(Request $request): RedirectResponse
    {
        if ($user = Auth::user()) {
            AuditLog::writeEntry([
                'user_id'    => $user->id,
                'event'      => 'auth.logout',
                'ip_address' => (string) $request->ip(),
                'user_agent' => (string) $request->userAgent(),
            ]);
        }

        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();
        return redirect()->route('home');
    }

    private function throttleKey(Request $request, string $email): string
    {
        return hash('sha256', mb_strtolower($email) . '|' . $request->ip());
    }
}

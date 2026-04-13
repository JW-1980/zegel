<?php

declare(strict_types=1);

namespace App\Http\Controllers\User;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\View\View;

class AccountController extends Controller
{
    public function edit(): View
    {
        return view('user.account.edit', ['user' => auth()->user()]);
    }

    public function updateProfile(Request $request): RedirectResponse
    {
        $user = $request->user();
        $data = $request->validate([
            'name'     => ['required', 'string', 'max:255'],
            'locale'   => ['nullable', 'string', 'in:en,nl,de,fr,es'],
            'timezone' => ['nullable', 'timezone'],
        ]);
        $user->forceFill($data)->save();

        AuditLog::writeEntry([
            'user_id'    => $user->id,
            'event'      => 'account.update_profile',
            'ip_address' => (string) $request->ip(),
            'user_agent' => (string) $request->userAgent(),
            'context'    => array_keys($data),
        ]);
        return back()->with('status', 'Profile updated.');
    }

    public function updatePassword(Request $request): RedirectResponse
    {
        $user = $request->user();
        $data = $request->validate([
            'current_password' => ['required', 'current_password'],
            'password'         => ['required', 'confirmed', PasswordRule::min(10)->mixedCase()->numbers()],
        ]);

        // Password history guard: prevent reuse of the last 5 passwords.
        $history = DB::table('password_history')->where('user_id', $user->id)->latest('created_at')->limit(5)->pluck('hash');
        foreach ($history as $old) {
            if (Hash::check($data['password'], $old)) {
                return back()->withErrors(['password' => 'Please choose a password you have not used before.']);
            }
        }

        $newHash = Hash::make($data['password']);
        $user->forceFill(['password' => $newHash])->save();
        DB::table('password_history')->insert([
            'user_id'    => $user->id,
            'hash'       => $newHash,
            'created_at' => now(),
        ]);

        AuditLog::writeEntry([
            'user_id'    => $user->id,
            'event'      => 'account.password_changed',
            'ip_address' => (string) $request->ip(),
            'user_agent' => (string) $request->userAgent(),
        ]);

        // Force re-login for safety.
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();
        return redirect()->route('login')->with('status', 'Password updated. Please sign in again.');
    }

    public function logoutEverywhere(Request $request): RedirectResponse
    {
        $user = $request->user();
        Auth::logoutOtherDevices((string) $request->input('current_password_confirm', ''));
        AuditLog::writeEntry([
            'user_id'    => $user->id,
            'event'      => 'account.logout_everywhere',
            'ip_address' => (string) $request->ip(),
            'user_agent' => (string) $request->userAgent(),
        ]);
        return back()->with('status', 'Signed out on all other devices.');
    }
}

<?php

declare(strict_types=1);

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class UsersController extends Controller
{
    public function index(Request $request): View
    {
        $q     = (string) $request->query('q', '');
        $users = User::query()
            ->when($q !== '', fn ($b) => $b->where(function ($w) use ($q) {
                $w->where('name', 'like', '%' . $q . '%')
                  ->orWhere('email', 'like', '%' . $q . '%');
            }))
            ->latest()
            ->paginate(25)
            ->withQueryString();
        return view('admin.users.index', compact('users', 'q'));
    }

    public function toggleActive(User $user): RedirectResponse
    {
        $this->guardSuperAdmin($user);
        $user->forceFill(['is_active' => !$user->is_active])->save();
        AuditLog::writeEntry([
            'user_id'      => auth()->id(),
            'event'        => 'admin.user.toggle_active',
            'ip_address'   => request()->ip(),
            'user_agent'   => (string) request()->userAgent(),
            'subject_type' => User::class,
            'subject_id'   => $user->id,
            'context'      => ['new_state' => $user->is_active],
        ]);
        return back()->with('status', __('User status updated.'));
    }

    public function toggleAdmin(User $user): RedirectResponse
    {
        $this->guardSuperAdmin($user);
        $user->forceFill(['is_admin' => !$user->is_admin])->save();
        return back()->with('status', __('Admin role updated.'));
    }

    private function guardSuperAdmin(User $user): void
    {
        if ($user->is_super_admin) {
            abort(403, __('Cannot modify the super administrator from the UI.'));
        }
    }
}

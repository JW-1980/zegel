@extends('layouts.app')

@section('content')
<div class="flex items-center justify-between">
    <h1 class="text-2xl font-bold tracking-tight">Users</h1>
    <form method="GET" action="{{ route('admin.users.index') }}">
        <input type="search" name="q" value="{{ $q }}" placeholder="Search name or email"
               class="w-64 rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm dark:border-slate-700 dark:bg-slate-950" />
    </form>
</div>

<div class="mt-6 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
    <table class="min-w-full divide-y divide-slate-200 dark:divide-slate-800">
        <thead class="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500 dark:bg-slate-900/40 dark:text-slate-400">
            <tr>
                <th class="px-4 py-3">Name</th>
                <th class="px-4 py-3">Email</th>
                <th class="px-4 py-3">Role</th>
                <th class="px-4 py-3">Status</th>
                <th class="px-4 py-3">Created</th>
                <th class="px-4 py-3"></th>
            </tr>
        </thead>
        <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
            @forelse($users as $u)
                <tr>
                    <td class="px-4 py-2 font-semibold">{{ $u->name }}</td>
                    <td class="px-4 py-2 text-sm">{{ $u->email }}</td>
                    <td class="px-4 py-2 text-sm">
                        @if($u->is_super_admin)
                            <span class="rounded-full bg-purple-100 px-2 py-0.5 text-xs font-semibold text-purple-800 dark:bg-purple-900/30 dark:text-purple-300">super admin</span>
                        @elseif($u->is_admin)
                            <span class="rounded-full bg-sky-100 px-2 py-0.5 text-xs font-semibold text-sky-800 dark:bg-sky-900/30 dark:text-sky-300">admin</span>
                        @else
                            <span class="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-300">user</span>
                        @endif
                    </td>
                    <td class="px-4 py-2 text-sm">{{ $u->is_active ? 'active' : 'suspended' }}</td>
                    <td class="px-4 py-2 text-xs text-slate-500">{{ $u->created_at?->diffForHumans() }}</td>
                    <td class="px-4 py-2 text-right text-sm">
                        @unless($u->is_super_admin)
                            <form method="POST" action="{{ route('admin.users.active', $u) }}" class="inline">
                                @csrf @method('PATCH')
                                <button class="text-sky-600 hover:text-sky-500">{{ $u->is_active ? 'suspend' : 'activate' }}</button>
                            </form>
                            ·
                            <form method="POST" action="{{ route('admin.users.admin', $u) }}" class="inline">
                                @csrf @method('PATCH')
                                <button class="text-sky-600 hover:text-sky-500">{{ $u->is_admin ? 'revoke admin' : 'make admin' }}</button>
                            </form>
                        @endunless
                    </td>
                </tr>
            @empty
                <tr><td colspan="6" class="py-10 text-center text-sm text-slate-500">No users found.</td></tr>
            @endforelse
        </tbody>
    </table>
</div>

<div class="mt-4">{{ $users->links() }}</div>
@endsection

@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-2xl">
    <h1 class="text-2xl font-bold tracking-tight">Account settings</h1>

    <form method="POST" action="{{ route('account.profile.update') }}"
          class="mt-6 space-y-4 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf @method('PUT')
        <h2 class="text-base font-semibold">Profile</h2>
        <label class="block">
            <span class="text-sm font-medium">Name</span>
            <input name="name" value="{{ $user->name }}" required class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <div class="grid gap-4 sm:grid-cols-2">
            <label class="block">
                <span class="text-sm font-medium">Locale</span>
                <select name="locale" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950">
                    @foreach(['en' => 'English', 'nl' => 'Nederlands', 'de' => 'Deutsch', 'fr' => 'Français', 'es' => 'Español'] as $code => $label)
                        <option value="{{ $code }}" @selected($user->locale === $code)>{{ $label }}</option>
                    @endforeach
                </select>
            </label>
            <label class="block">
                <span class="text-sm font-medium">Timezone</span>
                <input name="timezone" value="{{ $user->timezone }}" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
        </div>
        <button type="submit" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Save profile</button>
    </form>

    <form method="POST" action="{{ route('account.password.update') }}"
          class="mt-6 space-y-4 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf @method('PUT')
        <h2 class="text-base font-semibold">Change password</h2>
        <label class="block">
            <span class="text-sm font-medium">Current password</span>
            <input type="password" name="current_password" required autocomplete="current-password" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">New password</span>
            <input type="password" name="password" required autocomplete="new-password" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">Confirm new password</span>
            <input type="password" name="password_confirmation" required autocomplete="new-password" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <button type="submit" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Update password</button>
    </form>
</div>
@endsection

@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-md">
    <h1 class="text-2xl font-bold tracking-tight">Reset your password</h1>
    <form method="POST" action="{{ route('password.update') }}" class="mt-6 space-y-4 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf
        <input type="hidden" name="token" value="{{ $token }}" />
        <label class="block">
            <span class="text-sm font-medium">Email</span>
            <input type="email" name="email" value="{{ $email }}" required class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">New password</span>
            <input type="password" name="password" required autocomplete="new-password" autofocus class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">Confirm</span>
            <input type="password" name="password_confirmation" required autocomplete="new-password" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <button type="submit" class="w-full rounded-md bg-sky-600 px-3 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Update password</button>
    </form>
</div>
@endsection

@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-md">
    <h1 class="text-2xl font-bold tracking-tight">Sign in</h1>
    <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">Welcome back.</p>

    <form method="POST" action="{{ route('login') }}" class="mt-6 space-y-4 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf
        <label class="block">
            <span class="text-sm font-medium">Email</span>
            <input type="email" name="email" value="{{ old('email') }}" required autocomplete="email"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-sky-500 focus:ring-1 focus:ring-sky-500 dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">Password</span>
            <input type="password" name="password" required autocomplete="current-password"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="flex items-center gap-2 text-sm">
            <input type="checkbox" name="remember" value="1" class="rounded" />
            Keep me signed in on this device
        </label>
        <button type="submit" class="w-full rounded-md bg-sky-600 px-3 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">
            Sign in
        </button>
        <p class="text-center text-sm text-slate-600 dark:text-slate-400">
            No account? <a href="{{ route('register') }}" class="font-semibold text-sky-600">Create one</a>
        </p>
    </form>
</div>
@endsection

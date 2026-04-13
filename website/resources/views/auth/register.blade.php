@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-md">
    <h1 class="text-2xl font-bold tracking-tight">Create your account</h1>
    <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">Seal your files and share verifiable certificates.</p>

    <form method="POST" action="{{ route('register') }}" class="mt-6 space-y-4 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf
        <div class="absolute -left-[9999px]" aria-hidden="true">
            <label>If you are human, leave this field empty.<input type="text" name="honeypot" tabindex="-1" autocomplete="off"/></label>
        </div>
        <label class="block">
            <span class="text-sm font-medium">Full name</span>
            <input name="name" value="{{ old('name') }}" required autocomplete="name"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">Email</span>
            <input type="email" name="email" value="{{ old('email') }}" required autocomplete="email"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">Password</span>
            <input type="password" name="password" required autocomplete="new-password"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            <p class="mt-1 text-xs text-slate-500">Min 10 characters, mixed case + numbers, not compromised in known breaches.</p>
        </label>
        <label class="block">
            <span class="text-sm font-medium">Confirm password</span>
            <input type="password" name="password_confirmation" required autocomplete="new-password"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="flex items-start gap-2 text-sm">
            <input type="checkbox" name="accept_terms" value="1" required class="mt-0.5 rounded" />
            I agree to the <a href="{{ route('legal.terms') }}" class="font-semibold text-sky-600">Terms</a> and <a href="{{ route('legal.privacy') }}" class="font-semibold text-sky-600">Privacy Policy</a>.
        </label>
        <button type="submit" class="w-full rounded-md bg-sky-600 px-3 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">
            Create account
        </button>
        <p class="text-center text-sm text-slate-600 dark:text-slate-400">
            Already have one? <a href="{{ route('login') }}" class="font-semibold text-sky-600">Sign in</a>
        </p>
    </form>
</div>
@endsection

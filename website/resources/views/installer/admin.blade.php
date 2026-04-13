@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-2xl">
    <h1 class="text-3xl font-bold tracking-tight">Create the super administrator</h1>
    <p class="mt-2 text-slate-600 dark:text-slate-300">
        The super administrator can manage users, settings, and all sealed files.
    </p>

    <form method="POST" action="{{ route('installer.admin.store') }}"
          class="mt-8 space-y-5 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf
        <div class="grid gap-5 sm:grid-cols-2">
            <label class="block">
                <span class="text-sm font-medium">Name</span>
                <input name="name" value="{{ old('name') }}" required autocomplete="name"
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-sky-500 focus:ring-1 focus:ring-sky-500 dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Email</span>
                <input type="email" name="email" value="{{ old('email') }}" required autocomplete="email"
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm focus:border-sky-500 focus:ring-1 focus:ring-sky-500 dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block sm:col-span-1">
                <span class="text-sm font-medium">Password</span>
                <input type="password" name="password" required autocomplete="new-password"
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
                <p class="mt-1 text-xs text-slate-500">Min. 12 characters, mixed case + numbers + symbols.</p>
            </label>
            <label class="block sm:col-span-1">
                <span class="text-sm font-medium">Confirm password</span>
                <input type="password" name="password_confirmation" required autocomplete="new-password"
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
        </div>

        <hr class="border-slate-200 dark:border-slate-800" />

        <h2 class="text-base font-semibold">Site preferences</h2>
        <div class="grid gap-5 sm:grid-cols-2">
            <label class="block">
                <span class="text-sm font-medium">Site name</span>
                <input name="site_name" value="{{ old('site_name', 'Zegel') }}" required
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Tagline</span>
                <input name="site_tagline" value="{{ old('site_tagline', 'Tamper-proof file sealing') }}"
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Contact email</span>
                <input type="email" name="contact_email" value="{{ old('contact_email') }}"
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Max upload size (MB)</span>
                <input type="number" name="max_upload_mb" min="1" max="1024" value="{{ old('max_upload_mb', 25) }}" required
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Certificate issuer CN</span>
                <input name="certificate_issuer_cn" value="{{ old('certificate_issuer_cn', 'Zegel Certificate Authority') }}" required
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Certificate issuer organization</span>
                <input name="certificate_issuer_o" value="{{ old('certificate_issuer_o', 'Zegel Trust Services') }}" required
                       class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
        </div>

        <div class="space-y-2">
            <label class="flex items-center gap-2 text-sm">
                <input type="checkbox" name="allow_public_signup" value="1" {{ old('allow_public_signup', true) ? 'checked' : '' }} class="rounded" />
                Allow public signup
            </label>
            <label class="flex items-center gap-2 text-sm">
                <input type="checkbox" name="require_email_verification" value="1" {{ old('require_email_verification') ? 'checked' : '' }} class="rounded" />
                Require email verification
            </label>
            <label class="flex items-center gap-2 text-sm">
                <input type="checkbox" name="acknowledge_gdpr" value="1" required class="rounded" />
                I acknowledge the GDPR responsibilities as data controller
            </label>
        </div>

        <div class="flex items-center justify-end gap-3">
            <a href="{{ route('installer.database') }}" class="text-sm text-slate-600 hover:text-slate-900 dark:text-slate-300">Back</a>
            <button type="submit" class="rounded-lg bg-sky-600 px-5 py-2.5 text-sm font-semibold text-white shadow hover:bg-sky-500">
                Install Zegel
            </button>
        </div>
    </form>
</div>
@endsection

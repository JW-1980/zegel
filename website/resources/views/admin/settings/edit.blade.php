@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-2xl">
    <h1 class="text-2xl font-bold tracking-tight">Site settings</h1>
    <form method="POST" action="{{ route('admin.settings.update') }}"
          class="mt-6 space-y-5 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf @method('PUT')
        <div class="grid gap-4 sm:grid-cols-2">
            <label class="block">
                <span class="text-sm font-medium">Site name</span>
                <input name="site_name" value="{{ $settings['site_name'] }}" required class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Tagline</span>
                <input name="site_tagline" value="{{ $settings['site_tagline'] }}" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Contact email</span>
                <input type="email" name="contact_email" value="{{ $settings['contact_email'] }}" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Max upload size (MB)</span>
                <input type="number" name="max_upload_mb" min="1" max="1024" value="{{ $settings['max_upload_mb'] }}" required class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Certificate issuer CN</span>
                <input name="certificate_issuer_cn" value="{{ $settings['certificate_issuer_cn'] }}" required class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
            <label class="block">
                <span class="text-sm font-medium">Certificate issuer organization</span>
                <input name="certificate_issuer_o" value="{{ $settings['certificate_issuer_o'] }}" required class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm dark:border-slate-700 dark:bg-slate-950" />
            </label>
        </div>
        <div class="space-y-2">
            <label class="flex items-center gap-2 text-sm">
                <input type="checkbox" name="allow_public_signup" value="1" {{ $settings['allow_public_signup'] ? 'checked' : '' }} class="rounded" />
                Allow public signup
            </label>
            <label class="flex items-center gap-2 text-sm">
                <input type="checkbox" name="require_email_verification" value="1" {{ $settings['require_email_verification'] ? 'checked' : '' }} class="rounded" />
                Require email verification
            </label>
        </div>
        <div class="flex items-center justify-end">
            <button type="submit" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Save settings</button>
        </div>
    </form>
</div>
@endsection

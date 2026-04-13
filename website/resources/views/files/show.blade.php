@extends('layouts.app')

@php
    $issuer  = $cert['issuer']  ?? [];
    $subject = $cert['subject'] ?? [];
    $valid   = $cert['validity'] ?? [];
    $exts    = $cert['extensions'] ?? [];
    $fp      = $cert['fingerprints'] ?? [];
@endphp

@section('content')
<div class="grid gap-8 lg:grid-cols-5">
    <div class="lg:col-span-3">
        <section aria-labelledby="cert-title"
                 class="relative overflow-hidden rounded-3xl border border-amber-300/60 bg-gradient-to-br from-amber-50 via-white to-amber-100 p-8 shadow-2xl ring-1 ring-amber-300/40 print:shadow-none dark:border-amber-400/30 dark:from-amber-900/30 dark:via-slate-900 dark:to-amber-900/10">
            {{-- Guilloché background --}}
            <svg class="pointer-events-none absolute inset-0 h-full w-full opacity-[0.08]" viewBox="0 0 800 500" aria-hidden="true">
                <defs>
                    <pattern id="cert-pattern" width="60" height="60" patternUnits="userSpaceOnUse">
                        <circle cx="30" cy="30" r="28" fill="none" stroke="#b45309" stroke-width="0.5"/>
                        <circle cx="30" cy="30" r="22" fill="none" stroke="#b45309" stroke-width="0.5"/>
                        <circle cx="30" cy="30" r="16" fill="none" stroke="#b45309" stroke-width="0.5"/>
                    </pattern>
                </defs>
                <rect width="100%" height="100%" fill="url(#cert-pattern)"/>
            </svg>

            <header class="relative flex items-start justify-between">
                <div>
                    <p class="text-[10px] font-semibold uppercase tracking-[0.3em] text-amber-700 dark:text-amber-300">Certificate of Integrity</p>
                    <h1 id="cert-title" class="mt-1 font-serif text-3xl font-bold tracking-tight text-slate-900 dark:text-white">
                        This document is cryptographically sealed
                    </h1>
                </div>
                <div class="rounded-full border-2 border-amber-500/70 px-3 py-1 text-[10px] font-bold uppercase tracking-widest text-amber-700 dark:text-amber-300">
                    Zegel · v{{ $exts['zegel_version'] ?? '1.4' }}
                </div>
            </header>

            <p class="relative mt-6 font-serif text-sm leading-relaxed text-slate-700 dark:text-slate-300">
                <span class="text-amber-700 dark:text-amber-300">{{ $issuer['organization'] ?? 'Zegel Trust Services' }}</span>
                certifies that the file
                <span class="font-semibold">{{ $subject['original_filename'] ?? $file->original_filename }}</span>
                was sealed by
                <span class="font-semibold">{{ $subject['organization'] ?? 'an authenticated user' }}</span>
                on
                <span class="font-semibold">{{ \Carbon\Carbon::parse($valid['not_before'] ?? $file->created_at)->toFormattedDateString() }}</span>
                and has not been modified since. Any change, however small, renders the sealed content permanently undecryptable.
            </p>

            <dl class="relative mt-8 grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2">
                <div>
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Issuer</dt>
                    <dd class="mt-1 text-sm font-semibold text-slate-900 dark:text-white">{{ $issuer['common_name'] ?? '-' }}</dd>
                    <dd class="text-xs text-slate-600 dark:text-slate-400">{{ $issuer['organization'] ?? '' }} · {{ $issuer['organizational_unit'] ?? '' }}</dd>
                </div>
                <div>
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Subject</dt>
                    <dd class="mt-1 text-sm font-semibold text-slate-900 dark:text-white">{{ $subject['common_name'] ?? $file->subject_cn }}</dd>
                    <dd class="text-xs text-slate-600 dark:text-slate-400">{{ $subject['organization'] ?? '' }}</dd>
                </div>
                <div>
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Serial Number</dt>
                    <dd class="mt-1 font-mono text-xs text-slate-800 dark:text-slate-200 break-all">{{ $cert['serial_number'] ?? '—' }}</dd>
                </div>
                <div>
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Signature Algorithm</dt>
                    <dd class="mt-1 text-xs text-slate-800 dark:text-slate-200">{{ $cert['signature_algorithm'] ?? '' }}</dd>
                </div>
                <div>
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Valid From</dt>
                    <dd class="mt-1 text-xs text-slate-800 dark:text-slate-200">{{ \Carbon\Carbon::parse($valid['not_before'] ?? $file->created_at)->toDateTimeString() }} UTC</dd>
                </div>
                <div>
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Valid To</dt>
                    <dd class="mt-1 text-xs text-slate-800 dark:text-slate-200">{{ \Carbon\Carbon::parse($valid['not_after'] ?? $file->created_at->addYears(5))->toDateTimeString() }} UTC</dd>
                </div>
                <div class="sm:col-span-2">
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Merkle Root</dt>
                    <dd class="mt-1 font-mono text-[11px] text-slate-800 dark:text-slate-200 break-all">{{ $file->merkle_root_hex }}</dd>
                </div>
                <div class="sm:col-span-2">
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">SHA-1 Thumbprint</dt>
                    <dd class="mt-1 font-mono text-[11px] text-slate-800 dark:text-slate-200 break-all">{{ $fp['thumbprint_sha1'] ?? '' }}</dd>
                </div>
                <div class="sm:col-span-2">
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Key Usage</dt>
                    <dd class="mt-1 text-xs text-slate-800 dark:text-slate-200">{{ implode(' · ', $exts['key_usage'] ?? []) }}</dd>
                </div>
                @if(!empty($exts['zegel_flags']))
                <div class="sm:col-span-2">
                    <dt class="text-[10px] font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-300">Zegel Flags</dt>
                    <dd class="mt-1 flex flex-wrap gap-1">
                        @foreach($exts['zegel_flags'] as $flag)
                            <span class="rounded-full bg-amber-200/60 px-2 py-0.5 font-mono text-[10px] font-semibold text-amber-800 dark:bg-amber-500/20 dark:text-amber-200">{{ $flag }}</span>
                        @endforeach
                    </dd>
                </div>
                @endif
            </dl>

            <footer class="relative mt-10 flex items-end justify-between">
                <div>
                    <div class="font-serif text-xs text-slate-600 dark:text-slate-400">Issued by</div>
                    <div class="mt-1 font-serif text-lg italic text-slate-900 dark:text-white">{{ $issuer['organization'] ?? 'Zegel Trust Services' }}</div>
                </div>
                <div class="flex flex-col items-end">
                    <a href="{{ route('files.download', $file->public_id) }}"
                       class="inline-flex items-center gap-2 rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-amber-500">
                        <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 3v12m0 0l-4-4m4 4l4-4M4 17v2a2 2 0 002 2h12a2 2 0 002-2v-2"/></svg>
                        Download original .zgl
                    </a>
                    <p class="mt-2 text-[10px] text-slate-500">Clicks are counted once per visitor per 24h.</p>
                </div>
            </footer>
        </section>
    </div>

    <aside class="lg:col-span-2 space-y-6">
        <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <h2 class="text-sm font-semibold">Share this certificate</h2>
            <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">Anyone with the URL can view this page and download the original sealed file.</p>
            <div class="mt-3 flex items-stretch gap-2">
                <input id="share-url" readonly value="{{ $share }}"
                       class="flex-1 rounded-md border border-slate-300 bg-slate-50 px-3 py-2 font-mono text-xs text-slate-800 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-200" />
                <button type="button" id="copy-share"
                        class="rounded-md bg-slate-900 px-3 py-2 text-xs font-semibold text-white hover:bg-slate-700 dark:bg-white dark:text-slate-900">
                    Copy
                </button>
            </div>
            <p class="mt-3 text-xs text-slate-500 dark:text-slate-400">Or scan:</p>
            <div class="mt-1 flex justify-center">
                <img alt="QR code for {{ $file->title }}" class="h-40 w-40 rounded bg-white p-2"
                     src="{{ route('qr') }}?payload={{ urlencode($share) }}" loading="lazy"/>
            </div>
        </div>

        <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <h2 class="text-sm font-semibold">File details</h2>
            <dl class="mt-2 space-y-2 text-sm">
                <div class="flex justify-between"><dt class="text-slate-500">Blocks</dt><dd>{{ $file->block_count }}</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Size</dt><dd>{{ number_format($file->size_bytes / 1024, 1) }} KiB</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Views</dt><dd>{{ number_format($file->view_count) }}</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Downloads</dt><dd>{{ number_format($file->unique_download_count) }}</dd></div>
                <div class="flex justify-between"><dt class="text-slate-500">Visibility</dt><dd class="capitalize">{{ $file->visibility }}</dd></div>
            </dl>
            <div class="mt-4 space-y-2">
                <a href="{{ route('files.raw', $file->public_id) }}"
                   class="block w-full rounded-md border border-slate-300 px-3 py-2 text-center text-xs font-semibold text-slate-700 hover:bg-slate-100 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800">
                    View the original Zegel file
                </a>
            </div>
        </div>
    </aside>
</div>

<script nonce="{{ request()->attributes->get('csp_nonce') }}">
    document.getElementById('copy-share')?.addEventListener('click', async () => {
        const input = document.getElementById('share-url');
        try {
            await navigator.clipboard.writeText(input.value);
        } catch (_) {
            input.select();
            document.execCommand('copy');
        }
        const btn = document.getElementById('copy-share');
        const original = btn.textContent;
        btn.textContent = 'Copied ✓';
        setTimeout(() => btn.textContent = original, 1500);
    });
</script>
@endsection

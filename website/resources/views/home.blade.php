@extends('layouts.app')

@section('content')
<section class="relative overflow-hidden rounded-3xl bg-gradient-to-br from-slate-900 via-sky-900 to-indigo-900 px-6 py-16 text-white shadow-xl">
    <div class="mx-auto max-w-3xl text-center">
        <p class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-xs font-medium uppercase tracking-wider text-sky-200">
            Zegel Format v1.4 · RFC 6962 Merkle · AES-256-GCM
        </p>
        <h1 class="mt-4 text-4xl font-bold tracking-tight sm:text-5xl">Seal any file. Prove it was never changed.</h1>
        <p class="mt-4 text-lg text-sky-100/90">
            Zegel wraps your file in a container whose contents become physically unreadable if a single byte is ever modified.
            Upload a sealed file to get a shareable, verifiable certificate URL.
        </p>
        <div class="mt-8 flex flex-wrap items-center justify-center gap-3">
            <a href="{{ route('register') }}" class="rounded-lg bg-white px-5 py-2.5 text-sm font-semibold text-slate-900 shadow hover:bg-slate-100">Create your free account</a>
            <a href="{{ route('downloads.index') }}" class="rounded-lg border border-white/30 bg-white/10 px-5 py-2.5 text-sm font-semibold text-white hover:bg-white/20">Download Zegel apps</a>
        </div>
    </div>
</section>

<section class="mt-12 grid gap-6 sm:grid-cols-3">
    <div class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <div class="text-4xl font-bold text-sky-600">{{ number_format($stats['files_public']) }}</div>
        <div class="mt-1 text-sm uppercase tracking-wider text-slate-500 dark:text-slate-400">Public sealed files</div>
    </div>
    <div class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <div class="text-4xl font-bold text-emerald-600">{{ number_format($stats['files_total']) }}</div>
        <div class="mt-1 text-sm uppercase tracking-wider text-slate-500 dark:text-slate-400">Total files on the platform</div>
    </div>
    <div class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <div class="text-4xl font-bold text-purple-600">{{ number_format($stats['total_downloads']) }}</div>
        <div class="mt-1 text-sm uppercase tracking-wider text-slate-500 dark:text-slate-400">Unique certificate downloads</div>
    </div>
</section>

<section class="mt-12">
    <h2 class="text-xl font-semibold tracking-tight">Recently sealed, publicly verifiable</h2>
    <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">Anyone can view, verify, and download these files in their original sealed form.</p>
    @if($latest->isEmpty())
        <div class="mt-6 rounded-2xl border border-dashed border-slate-300 bg-white p-10 text-center text-slate-500 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-400">
            Nothing public yet. <a class="font-semibold text-sky-600" href="{{ route('register') }}">Be the first to seal a file.</a>
        </div>
    @else
        <div class="mt-6 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            @foreach($latest as $file)
                <a href="{{ route('files.show', $file->public_id) }}"
                   class="group rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:border-sky-300 hover:shadow-md dark:border-slate-800 dark:bg-slate-900">
                    <div class="flex items-center gap-2 text-xs uppercase tracking-wider text-sky-600 group-hover:text-sky-500">
                        <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l8 4v6c0 5-3.5 9-8 10-4.5-1-8-5-8-10V6l8-4z"/></svg>
                        Zegel Certificate
                    </div>
                    <h3 class="mt-2 text-lg font-semibold text-slate-900 dark:text-white">{{ $file->title }}</h3>
                    <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">{{ $file->original_filename }}</p>
                    <p class="mt-3 truncate font-mono text-[11px] text-slate-400">{{ Str::limit($file->merkle_root_hex, 48) }}</p>
                </a>
            @endforeach
        </div>
    @endif
</section>
@endsection

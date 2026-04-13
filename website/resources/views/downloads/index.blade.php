@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-4xl">
    <h1 class="text-3xl font-bold tracking-tight">Download Zegel</h1>
    <p class="mt-2 text-slate-600 dark:text-slate-300">
        Official Zegel {{ $downloads['version'] }} builds for every supported platform. Each release is signed with
        <code class="rounded bg-slate-100 px-1 font-mono text-xs dark:bg-slate-800">{{ $downloads['signature_algorithm'] }}</code>
        and ships with a SHA-256 checksum.
    </p>

    <div class="mt-10 space-y-6">
        @foreach($downloads['platforms'] as $platform)
            <section class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
                <header class="flex items-center justify-between">
                    <div>
                        <h2 class="text-xl font-semibold">{{ $platform['name'] }}</h2>
                        <p class="mt-1 text-sm text-slate-500">{{ $platform['notes'] }}</p>
                    </div>
                    <span class="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-slate-600 dark:bg-slate-800 dark:text-slate-300">{{ $platform['key'] }}</span>
                </header>
                <div class="mt-4 grid gap-3 sm:grid-cols-2">
                    @foreach($platform['assets'] as $asset)
                        <div class="flex items-center justify-between rounded-xl border border-slate-200 p-4 dark:border-slate-800">
                            <div>
                                <div class="flex items-center gap-2 text-sm font-semibold">
                                    <span class="rounded bg-sky-100 px-2 py-0.5 text-[10px] font-bold uppercase text-sky-700 dark:bg-sky-900/50 dark:text-sky-200">{{ $asset['kind'] }}</span>
                                    <span>{{ $asset['arch'] }}</span>
                                </div>
                                <div class="mt-1 break-all text-xs text-slate-500">{{ $asset['filename'] }}</div>
                                <div class="mt-1 text-[11px] text-slate-400">~{{ number_format($asset['size'] / 1024 / 1024, 1) }} MB</div>
                            </div>
                            <a href="{{ url($downloads['download_base'] . '/' . $asset['filename']) }}"
                               class="rounded-md bg-sky-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-sky-500">
                                Download
                            </a>
                        </div>
                    @endforeach
                </div>
            </section>
        @endforeach
    </div>

    <section class="mt-10 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900 dark:border-amber-900/40 dark:bg-amber-900/20 dark:text-amber-200">
        <h2 class="text-base font-semibold">Verify every download</h2>
        <ol class="mt-2 list-decimal pl-5 space-y-1">
            <li>Compare the published SHA-256 checksum to your local file.</li>
            <li>Then verify the binary's signature with the Zegel release public key.</li>
            <li>Only run builds whose checksum and signature match.</li>
        </ol>
    </section>
</div>
@endsection

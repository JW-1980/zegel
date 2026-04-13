@extends('layouts.app')

@section('content')
<div class="mb-6">
    <a href="{{ route('files.show', $file->public_id) }}" class="text-sm text-sky-600 hover:text-sky-500">&larr; Back to certificate</a>
</div>
<h1 class="text-2xl font-bold tracking-tight">Original Zegel file</h1>
<p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
    Total size: {{ number_format($total_length) }} bytes · Merkle root:
    <code class="rounded bg-slate-100 px-1 font-mono text-xs dark:bg-slate-800">{{ $file->merkle_root_hex }}</code>
</p>

<section class="mt-6 overflow-hidden rounded-2xl border border-slate-200 bg-slate-950 p-4 text-slate-200 shadow-inner dark:border-slate-800">
    <h2 class="mb-2 text-xs font-semibold uppercase tracking-wider text-slate-400">Hex preview (first 4 KiB)</h2>
    <pre class="overflow-x-auto font-mono text-[11px] leading-relaxed whitespace-pre">{{ $preview_hex }}</pre>
    @if($truncated)
        <p class="mt-2 text-xs text-slate-500">Preview truncated. <a href="{{ route('files.download', $file->public_id) }}" class="text-sky-400 hover:text-sky-300">Download the full file</a> to inspect the rest.</p>
    @endif
</section>
@endsection

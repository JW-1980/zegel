@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-2xl">
    <h1 class="text-2xl font-bold tracking-tight">Verify a Zegel file</h1>
    <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
        Upload a sealed .zgl file. We inspect the header structurally. If you
        also paste the master key, we cryptographically verify and discard the
        file immediately — no storage, no logging of file contents.
    </p>

    <form method="POST" action="{{ route('verify.run') }}" enctype="multipart/form-data"
          class="mt-6 space-y-4 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf
        <label class="block">
            <span class="text-sm font-medium">.zgl file</span>
            <input type="file" name="zegel_file" required class="mt-1 block w-full text-sm" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">Master key (optional, 64 hex chars)</span>
            <input type="text" name="master_key" pattern="^[0-9a-fA-F]{64}$" maxlength="64"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 font-mono text-xs shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <button type="submit" class="w-full rounded-md bg-sky-600 px-3 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Verify</button>
    </form>

    @isset($result)
        <div class="mt-6 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <h2 class="text-base font-semibold">Result</h2>
            @if($result['error'])
                <div class="mt-2 rounded border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800 dark:border-rose-900 dark:bg-rose-900/30 dark:text-rose-200">
                    {{ $result['error'] }}
                </div>
            @endif
            @if(!empty($result['inspection']))
                <dl class="mt-3 grid gap-2 text-sm sm:grid-cols-2">
                    <div><dt class="text-slate-500">Version</dt><dd>{{ $result['inspection']->versionString() }}</dd></div>
                    <div><dt class="text-slate-500">Blocks</dt><dd>{{ $result['inspection']->blockCount }}</dd></div>
                    <div><dt class="text-slate-500">Filename</dt><dd>{{ $result['inspection']->filename ?? '—' }}</dd></div>
                    <div><dt class="text-slate-500">Content-Type</dt><dd>{{ $result['inspection']->contentType ?? '—' }}</dd></div>
                    <div class="sm:col-span-2"><dt class="text-slate-500">Merkle root</dt><dd class="font-mono break-all">{{ $result['inspection']->merkleRootHex }}</dd></div>
                </dl>
            @endif
            @if(isset($result['valid']) && $result['valid'] === true)
                <p class="mt-3 inline-flex items-center gap-2 rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-200">
                    Valid · Merkle root + Master seal OK
                </p>
            @elseif(isset($result['valid']) && $result['valid'] === false)
                <p class="mt-3 inline-flex items-center gap-2 rounded-full bg-rose-100 px-3 py-1 text-xs font-semibold text-rose-800 dark:bg-rose-900/30 dark:text-rose-200">
                    Tampered or wrong key
                </p>
            @endif
        </div>
    @endisset
</div>
@endsection

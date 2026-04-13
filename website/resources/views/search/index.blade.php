@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-3xl">
    <h1 class="text-2xl font-bold tracking-tight">Search public Zegel files</h1>
    <form method="GET" action="{{ route('search') }}" class="mt-4 flex gap-2">
        <input type="search" name="q" value="{{ $q }}" placeholder="Search title, filename, or Merkle root"
               class="flex-1 rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        <button type="submit" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Search</button>
    </form>

    @if($q !== '')
        <p class="mt-4 text-sm text-slate-500">{{ $results->count() }} result{{ $results->count() === 1 ? '' : 's' }} for "{{ $q }}"</p>
        <ul class="mt-4 divide-y divide-slate-200 dark:divide-slate-800">
            @foreach($results as $file)
                <li class="py-3">
                    <a href="{{ route('files.show', $file->public_id) }}" class="font-semibold text-slate-900 hover:text-sky-600 dark:text-white">{{ $file->title }}</a>
                    <p class="text-xs text-slate-500">{{ $file->original_filename }}</p>
                    <p class="font-mono text-[11px] text-slate-400 break-all">{{ $file->merkle_root_hex }}</p>
                </li>
            @endforeach
            @if($results->isEmpty())
                <li class="py-6 text-center text-sm text-slate-500">No matches.</li>
            @endif
        </ul>
    @endif
</div>
@endsection

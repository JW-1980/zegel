@extends('layouts.app')

@section('content')
<div class="flex flex-wrap items-center justify-between gap-3">
    <div>
        <h1 class="text-2xl font-bold tracking-tight">Welcome back, {{ auth()->user()->name }}</h1>
        <p class="text-sm text-slate-600 dark:text-slate-400">Here is an overview of your sealed files.</p>
    </div>
    <a href="{{ route('user.files.create') }}" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Upload a Zegel file</a>
</div>

<div class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
    @foreach([
        ['label' => 'Files',            'value' => $totals['files'],            'color' => 'sky'],
        ['label' => 'Public',           'value' => $totals['public'],           'color' => 'emerald'],
        ['label' => 'Private',          'value' => $totals['private'],          'color' => 'rose'],
        ['label' => 'Unique downloads', 'value' => $totals['unique_downloads'], 'color' => 'purple'],
    ] as $tile)
        <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div class="text-xs font-medium uppercase tracking-wider text-slate-500 dark:text-slate-400">{{ $tile['label'] }}</div>
            <div class="mt-1 text-3xl font-bold text-{{ $tile['color'] }}-600">{{ number_format($tile['value']) }}</div>
        </div>
    @endforeach
</div>

<div class="mt-8 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
    <h2 class="text-base font-semibold">Recent files</h2>
    @if($recent->isEmpty())
        <p class="mt-2 text-sm text-slate-500">You haven't uploaded a file yet. <a href="{{ route('user.files.create') }}" class="font-semibold text-sky-600">Upload your first .zgl</a>.</p>
    @else
        <ul class="mt-3 divide-y divide-slate-200 dark:divide-slate-800">
            @foreach($recent as $file)
                <li class="flex items-center justify-between py-3">
                    <div class="min-w-0">
                        <a href="{{ route('files.show', $file->public_id) }}" class="truncate text-sm font-semibold text-slate-900 hover:text-sky-600 dark:text-white">{{ $file->title }}</a>
                        <p class="truncate text-xs text-slate-500">{{ $file->original_filename }}</p>
                    </div>
                    <span class="rounded-full px-2 py-0.5 text-xs font-medium
                        @class([
                            'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300' => $file->visibility === 'public',
                            'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-200' => $file->visibility === 'unlisted',
                            'bg-slate-200 text-slate-700 dark:bg-slate-800 dark:text-slate-300' => $file->visibility === 'private',
                        ])
                    ">{{ $file->visibility }}</span>
                </li>
            @endforeach
        </ul>
    @endif
</div>
@endsection

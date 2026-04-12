@extends('layouts.app')

@section('content')
<h1 class="text-2xl font-bold tracking-tight">Admin dashboard</h1>

<div class="mt-6 grid gap-4 sm:grid-cols-3 xl:grid-cols-6">
    @foreach($totals as $k => $v)
        <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div class="text-xs font-medium uppercase tracking-wider text-slate-500">{{ str_replace('_',' ', $k) }}</div>
            <div class="mt-1 text-2xl font-bold">{{ number_format((int) $v) }}</div>
        </div>
    @endforeach
</div>

<div class="mt-8 grid gap-6 lg:grid-cols-2">
    <div class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <h2 class="text-base font-semibold">Recent files</h2>
        <ul class="mt-3 divide-y divide-slate-200 dark:divide-slate-800">
            @foreach($recentFiles as $f)
                <li class="flex items-center justify-between py-2">
                    <a href="{{ route('files.show', $f->public_id) }}" class="text-sm font-semibold text-slate-900 hover:text-sky-600 dark:text-white">{{ $f->title }}</a>
                    <span class="text-xs text-slate-500">{{ $f->created_at->diffForHumans() }}</span>
                </li>
            @endforeach
        </ul>
    </div>
    <div class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <h2 class="text-base font-semibold">Recent audit entries</h2>
        <ul class="mt-3 divide-y divide-slate-200 dark:divide-slate-800">
            @foreach($recentAudits as $a)
                <li class="py-2 text-sm">
                    <div class="font-semibold text-slate-900 dark:text-white">{{ $a->event }}</div>
                    <div class="text-xs text-slate-500">{{ $a->ip_address }} · {{ $a->created_at->diffForHumans() }}</div>
                </li>
            @endforeach
        </ul>
    </div>
</div>

<div class="mt-8 flex gap-4">
    <a href="{{ route('admin.users.index') }}" class="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-semibold hover:bg-slate-100 dark:border-slate-700 dark:hover:bg-slate-800">Manage users</a>
    <a href="{{ route('admin.settings.edit') }}" class="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-semibold hover:bg-slate-100 dark:border-slate-700 dark:hover:bg-slate-800">Site settings</a>
</div>
@endsection

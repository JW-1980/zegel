@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-3xl">
    <h1 class="text-3xl font-bold tracking-tight">Welcome to the Zegel installation wizard</h1>
    <p class="mt-2 text-slate-600 dark:text-slate-300">
        This short wizard prepares the database, creates your super-administrator account, and records site preferences.
        It runs exactly once.
    </p>

    <section class="mt-8 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        <h2 class="text-lg font-semibold">Environment checks</h2>
        <ul class="mt-3 space-y-2 text-sm">
            @foreach($checks as $c)
                <li class="flex items-start justify-between gap-4 rounded-lg border border-slate-100 px-3 py-2 dark:border-slate-800">
                    <span>{{ $c['label'] }}</span>
                    <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold
                        {{ $c['ok'] ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300' : 'bg-rose-100 text-rose-800 dark:bg-rose-900/30 dark:text-rose-300' }}">
                        {{ $c['ok'] ? 'OK' : 'Fix' }} · {{ \Illuminate\Support\Str::limit($c['detail'], 36) }}
                    </span>
                </li>
            @endforeach
        </ul>
    </section>

    <div class="mt-8 flex items-center justify-end">
        <a href="{{ route('installer.database') }}"
           class="rounded-lg bg-sky-600 px-5 py-2.5 text-sm font-semibold text-white shadow hover:bg-sky-500">
            Continue
        </a>
    </div>
</div>
@endsection

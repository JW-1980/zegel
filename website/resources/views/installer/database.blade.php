@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-2xl">
    <h1 class="text-3xl font-bold tracking-tight">Prepare the database</h1>
    <p class="mt-2 text-slate-600 dark:text-slate-300">
        Zegel will now run all database migrations. The connection is read from <code class="rounded bg-slate-100 px-1 font-mono text-xs dark:bg-slate-800">.env</code>.
    </p>

    <form method="POST" action="{{ route('installer.database.store') }}"
          class="mt-8 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf
        <ul class="space-y-2 text-sm text-slate-600 dark:text-slate-300">
            <li>• Creates users, sessions, settings, files, downloads, audit</li>
            <li>• Uses Laravel's transactional migrations when available</li>
            <li>• Safe to re-run — migrations are idempotent</li>
        </ul>
        <div class="mt-6 flex items-center justify-end gap-3">
            <a href="{{ route('installer.welcome') }}" class="text-sm text-slate-600 hover:text-slate-900 dark:text-slate-300">Back</a>
            <button type="submit" class="rounded-lg bg-sky-600 px-5 py-2.5 text-sm font-semibold text-white shadow hover:bg-sky-500">
                Run migrations
            </button>
        </div>
    </form>
</div>
@endsection

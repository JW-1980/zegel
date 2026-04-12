@extends('layouts.app')

@section('content')
<h1 class="text-2xl font-bold tracking-tight">Audit log</h1>
<p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
    Chain status:
    @if($chainValid)
        <span class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-200">
            Hash chain populated
        </span>
    @else
        <span class="inline-flex items-center gap-1 rounded-full bg-rose-100 px-2 py-0.5 text-xs font-semibold text-rose-800 dark:bg-rose-900/30 dark:text-rose-200">
            Chain gap detected
        </span>
    @endif
</p>

<form method="GET" class="mt-4 flex gap-2">
    <input name="event" value="{{ $event }}" placeholder="Event name filter"
           class="w-64 rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm dark:border-slate-700 dark:bg-slate-950" />
    <button class="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-semibold hover:bg-slate-100 dark:border-slate-700 dark:hover:bg-slate-800">Filter</button>
</form>

<div class="mt-6 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
    <table class="min-w-full divide-y divide-slate-200 dark:divide-slate-800">
        <thead class="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500 dark:bg-slate-900/40 dark:text-slate-400">
            <tr>
                <th class="px-4 py-3">Time</th>
                <th class="px-4 py-3">Event</th>
                <th class="px-4 py-3">User</th>
                <th class="px-4 py-3">IP</th>
                <th class="px-4 py-3">Chain hash (first 12)</th>
            </tr>
        </thead>
        <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
            @forelse($logs as $log)
                <tr>
                    <td class="px-4 py-2 text-xs text-slate-500">{{ $log->created_at?->toDateTimeString() }}</td>
                    <td class="px-4 py-2 text-sm"><code>{{ $log->event }}</code></td>
                    <td class="px-4 py-2 text-sm">{{ $log->user_id ?? '—' }}</td>
                    <td class="px-4 py-2 text-xs">{{ $log->ip_address ?? '—' }}</td>
                    <td class="px-4 py-2 font-mono text-[11px] text-slate-400">{{ substr($log->hash_chain ?? '', 0, 12) }}…</td>
                </tr>
            @empty
                <tr><td colspan="5" class="px-4 py-10 text-center text-sm text-slate-500">No entries yet.</td></tr>
            @endforelse
        </tbody>
    </table>
</div>
<div class="mt-4">{{ $logs->links() }}</div>
@endsection

@extends('layouts.app')

@section('content')
<div class="flex items-center justify-between">
    <h1 class="text-2xl font-bold tracking-tight">Your Zegel files</h1>
    <a href="{{ route('user.files.create') }}" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Upload</a>
</div>

<div class="mt-6 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
    <table class="min-w-full divide-y divide-slate-200 dark:divide-slate-800">
        <thead class="bg-slate-50 dark:bg-slate-900/40">
            <tr class="text-left text-xs uppercase tracking-wider text-slate-500 dark:text-slate-400">
                <th class="px-4 py-3">Title</th>
                <th class="px-4 py-3">Visibility</th>
                <th class="px-4 py-3">Blocks</th>
                <th class="px-4 py-3">Size</th>
                <th class="px-4 py-3">Downloads</th>
                <th class="px-4 py-3"></th>
            </tr>
        </thead>
        <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
            @forelse($files as $file)
                <tr>
                    <td class="px-4 py-3">
                        <a href="{{ route('files.show', $file->public_id) }}" class="font-semibold text-slate-900 hover:text-sky-600 dark:text-white">{{ $file->title }}</a>
                        <div class="text-xs text-slate-500">{{ $file->original_filename }}</div>
                    </td>
                    <td class="px-4 py-3">
                        <form method="POST" action="{{ route('user.files.visibility', $file) }}">
                            @csrf @method('PATCH')
                            <select name="visibility" onchange="this.form.submit()" class="rounded-md border border-slate-300 bg-white px-2 py-1 text-xs dark:border-slate-700 dark:bg-slate-950">
                                @foreach(['public','unlisted','private'] as $v)
                                    <option value="{{ $v }}" @selected($file->visibility === $v)>{{ $v }}</option>
                                @endforeach
                            </select>
                        </form>
                    </td>
                    <td class="px-4 py-3 text-sm">{{ $file->block_count }}</td>
                    <td class="px-4 py-3 text-sm">{{ number_format($file->size_bytes / 1024, 1) }} KiB</td>
                    <td class="px-4 py-3 text-sm">{{ number_format($file->unique_download_count) }}</td>
                    <td class="px-4 py-3 text-right">
                        <form method="POST" action="{{ route('user.files.destroy', $file) }}" onsubmit="return confirm('Delete this file?');">
                            @csrf @method('DELETE')
                            <button type="submit" class="text-sm text-rose-600 hover:text-rose-500">Delete</button>
                        </form>
                    </td>
                </tr>
            @empty
                <tr><td colspan="6" class="px-4 py-10 text-center text-sm text-slate-500">You haven't uploaded anything yet.</td></tr>
            @endforelse
        </tbody>
    </table>
</div>

<div class="mt-4">{{ $files->links() }}</div>
@endsection

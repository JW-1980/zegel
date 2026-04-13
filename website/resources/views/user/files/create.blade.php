@extends('layouts.app')

@section('content')
<div class="mx-auto max-w-2xl">
    <h1 class="text-2xl font-bold tracking-tight">Upload a Zegel file</h1>
    <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
        Upload a <code class="rounded bg-slate-100 px-1 font-mono text-xs dark:bg-slate-800">.zgl</code> file that you already sealed with the Zegel CLI, GUI, or library.
        We never ask for the master key — only the sealed container is stored.
    </p>

    <form method="POST" action="{{ route('user.files.store') }}" enctype="multipart/form-data"
          class="mt-6 space-y-5 rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
        @csrf
        <label class="block">
            <span class="text-sm font-medium">Title</span>
            <input name="title" required maxlength="200" value="{{ old('title') }}"
                   class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950" />
        </label>
        <label class="block">
            <span class="text-sm font-medium">Description (optional)</span>
            <textarea name="description" rows="3" maxlength="2000"
                      class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950">{{ old('description') }}</textarea>
        </label>
        <label class="block">
            <span class="text-sm font-medium">Visibility</span>
            <select name="visibility" class="mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm dark:border-slate-700 dark:bg-slate-950">
                <option value="private" @selected(old('visibility') === 'private')>Private (only you + admin)</option>
                <option value="unlisted" @selected(old('visibility') === 'unlisted')>Unlisted (accessible via direct link)</option>
                <option value="public" @selected(old('visibility', 'public') === 'public')>Public (listed on the homepage)</option>
            </select>
        </label>
        <div class="block">
            <span class="text-sm font-medium">Sealed .zgl file</span>
            <label data-dropzone data-max-mb="{{ \App\Models\SiteSetting::getValue('max_upload_mb', 25) }}"
                   class="mt-1 flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-slate-300 bg-slate-50 px-4 py-8 text-center text-sm text-slate-600 transition hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-300 dark:hover:bg-slate-900">
                <svg class="h-8 w-8 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M7 16V7a5 5 0 0110 0v9a4 4 0 01-8 0v-7a2 2 0 014 0v8"/></svg>
                <p>Drop a <code class="rounded bg-slate-100 px-1 dark:bg-slate-900">.zgl</code> file here or click to browse</p>
                <p class="text-xs text-slate-500" data-dropzone-label>No file chosen</p>
                <input type="file" name="zegel_file" accept=".zgl,application/x-zgl,application/octet-stream" required class="sr-only" />
            </label>
            <p class="mt-1 text-xs text-slate-500">Max {{ \App\Models\SiteSetting::getValue('max_upload_mb', 25) }} MB. We inspect the file's header without needing the master key.</p>
        </div>
        <div class="flex items-center justify-end gap-3">
            <a href="{{ route('user.files.index') }}" class="text-sm text-slate-600 hover:text-slate-900 dark:text-slate-300">Cancel</a>
            <button type="submit" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Upload</button>
        </div>
    </form>
</div>
@endsection

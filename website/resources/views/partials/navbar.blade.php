@php
    $siteName = \App\Models\SiteSetting::getValue('site_name', 'Zegel');
    $user = auth()->user();
@endphp
<nav class="sticky top-0 z-30 border-b border-slate-200/70 bg-white/90 backdrop-blur supports-[backdrop-filter]:bg-white/70 dark:border-slate-800/70 dark:bg-slate-950/90">
    <div class="mx-auto flex h-16 w-full max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        <div class="flex items-center gap-3">
            <a href="{{ route('home') }}" class="flex items-center gap-2 text-lg font-semibold tracking-tight">
                <svg class="h-7 w-7 text-sky-600" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                    <path d="M12 2l8 4v6c0 5-3.5 9-8 10-4.5-1-8-5-8-10V6l8-4z" fill="currentColor" opacity="0.15"/>
                    <path d="M12 2l8 4v6c0 5-3.5 9-8 10-4.5-1-8-5-8-10V6l8-4z" stroke="currentColor" stroke-width="1.5"/>
                    <path d="M8 12.5l3 3 5-6" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
                <span>{{ $siteName }}</span>
            </a>
        </div>
        <div class="hidden items-center gap-6 md:flex">
            <a href="{{ route('home') }}" class="text-sm font-medium text-slate-600 hover:text-sky-600 dark:text-slate-300 dark:hover:text-sky-400">Home</a>
            <a href="{{ route('downloads.index') }}" class="text-sm font-medium text-slate-600 hover:text-sky-600 dark:text-slate-300 dark:hover:text-sky-400">Downloads</a>
            <a href="{{ route('search') }}" class="text-sm font-medium text-slate-600 hover:text-sky-600 dark:text-slate-300 dark:hover:text-sky-400">Search</a>
            <a href="{{ route('verify.show') }}" class="text-sm font-medium text-slate-600 hover:text-sky-600 dark:text-slate-300 dark:hover:text-sky-400">Verify</a>
            <a href="{{ route('legal.privacy') }}" class="text-sm font-medium text-slate-600 hover:text-sky-600 dark:text-slate-300 dark:hover:text-sky-400">Privacy</a>
        </div>
        <div class="flex items-center gap-3">
            <button type="button" data-theme-toggle aria-label="Toggle dark mode"
                    class="hidden rounded-md border border-slate-300 p-1.5 text-slate-600 hover:bg-slate-100 dark:border-slate-700 dark:text-slate-300 dark:hover:bg-slate-800 sm:inline-flex">
                <svg class="h-4 w-4 dark:hidden" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/></svg>
                <svg class="h-4 w-4 hidden dark:block" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path stroke-linecap="round" stroke-linejoin="round" d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>
            </button>
            @auth
                <a href="{{ route('user.files.create') }}" class="hidden rounded-md bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white shadow hover:bg-sky-500 sm:inline-flex">Upload</a>
                <a href="{{ route('user.dashboard') }}" class="hidden text-sm font-medium text-slate-600 hover:text-sky-600 dark:text-slate-300 sm:inline">Dashboard</a>
                @if($user?->isAdmin())
                    <a href="{{ route('admin.dashboard') }}" class="hidden text-sm font-medium text-purple-700 hover:text-purple-500 dark:text-purple-300 sm:inline">Admin</a>
                @endif
                <form method="POST" action="{{ route('logout') }}">
                    @csrf
                    <button type="submit" class="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-100 dark:border-slate-700 dark:text-slate-200 dark:hover:bg-slate-800">Sign out</button>
                </form>
            @else
                <a href="{{ route('login') }}" class="text-sm font-medium text-slate-700 hover:text-sky-600 dark:text-slate-200">Sign in</a>
                <a href="{{ route('register') }}" class="rounded-md bg-slate-900 px-3 py-1.5 text-sm font-semibold text-white shadow hover:bg-slate-700 dark:bg-white dark:text-slate-900 dark:hover:bg-slate-100">Sign up</a>
            @endauth
        </div>
    </div>
</nav>

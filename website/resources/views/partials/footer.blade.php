<footer class="mt-16 border-t border-slate-200/70 bg-white py-10 text-slate-600 dark:border-slate-800/70 dark:bg-slate-950 dark:text-slate-400">
    <div class="mx-auto grid w-full max-w-7xl gap-8 px-4 sm:grid-cols-2 sm:px-6 lg:grid-cols-4 lg:px-8">
        <div>
            <div class="flex items-center gap-2 font-semibold text-slate-900 dark:text-white">
                <svg class="h-5 w-5 text-sky-600" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l8 4v6c0 5-3.5 9-8 10-4.5-1-8-5-8-10V6l8-4z"/></svg>
                Zegel
            </div>
            <p class="mt-2 text-sm">Tamper-proof file sealing for the open web.</p>
        </div>
        <div>
            <div class="text-sm font-semibold text-slate-900 dark:text-white">Product</div>
            <ul class="mt-2 space-y-1 text-sm">
                <li><a href="{{ route('downloads.index') }}" class="hover:text-sky-600 dark:hover:text-sky-400">Downloads</a></li>
                <li><a href="{{ route('home') }}" class="hover:text-sky-600 dark:hover:text-sky-400">Showcase</a></li>
            </ul>
        </div>
        <div>
            <div class="text-sm font-semibold text-slate-900 dark:text-white">Legal</div>
            <ul class="mt-2 space-y-1 text-sm">
                <li><a href="{{ route('legal.privacy') }}" class="hover:text-sky-600 dark:hover:text-sky-400">Privacy Policy</a></li>
                <li><a href="{{ route('legal.terms') }}" class="hover:text-sky-600 dark:hover:text-sky-400">Terms of Service</a></li>
                <li><a href="{{ route('legal.cookies') }}" class="hover:text-sky-600 dark:hover:text-sky-400">Cookie Policy</a></li>
                <li><a href="{{ route('legal.dpa') }}" class="hover:text-sky-600 dark:hover:text-sky-400">DPA</a></li>
                <li><a href="{{ route('legal.imprint') }}" class="hover:text-sky-600 dark:hover:text-sky-400">Imprint</a></li>
            </ul>
        </div>
        <div>
            <div class="text-sm font-semibold text-slate-900 dark:text-white">Status</div>
            <ul class="mt-2 space-y-1 text-sm">
                <li>
                    <span class="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300">
                        <span class="h-1.5 w-1.5 rounded-full bg-emerald-500"></span>
                        All systems operational
                    </span>
                </li>
                <li><a href="/up" class="hover:text-sky-600 dark:hover:text-sky-400">Health check</a></li>
            </ul>
        </div>
    </div>
    <div class="mx-auto mt-8 w-full max-w-7xl px-4 text-center text-xs sm:px-6 lg:px-8">
        © {{ date('Y') }} Zegel project · Format v1.4 · Built with Laravel {{ app()->version() }}
    </div>
</footer>

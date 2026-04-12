@php
    $hasConsent = request()->cookie('zg_consent');
@endphp
@unless($hasConsent)
<div id="zg-cookie" aria-label="Cookie consent" role="dialog"
     class="fixed inset-x-4 bottom-4 z-40 rounded-xl border border-slate-200 bg-white p-4 shadow-2xl dark:border-slate-700 dark:bg-slate-900 sm:left-auto sm:right-4 sm:max-w-md">
    <h2 class="text-sm font-semibold text-slate-900 dark:text-white">Cookies &amp; privacy</h2>
    <p class="mt-1 text-xs text-slate-600 dark:text-slate-300">
        We use only strictly necessary cookies for login and CSRF protection. Analytics and marketing are disabled by default.
        See our <a href="{{ route('legal.cookies') }}" class="text-sky-600 underline">Cookie Policy</a>.
    </p>
    <div class="mt-3 flex flex-col gap-2 sm:flex-row">
        <button type="button" data-consent="accept"
                class="inline-flex flex-1 items-center justify-center rounded-md bg-sky-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-sky-500">
            Accept necessary
        </button>
        <button type="button" data-consent="reject"
                class="inline-flex flex-1 items-center justify-center rounded-md border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-700 hover:bg-slate-100 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-800">
            Reject optional
        </button>
    </div>
</div>
<script nonce="{{ request()->attributes->get('csp_nonce') }}">
(function () {
    const banner = document.getElementById('zg-cookie');
    if (!banner) return;
    banner.querySelectorAll('[data-consent]').forEach(function (btn) {
        btn.addEventListener('click', async function () {
            const action = btn.getAttribute('data-consent');
            try {
                await fetch(@json(route('gdpr.consent')), {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                        'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]').getAttribute('content'),
                    },
                    body: JSON.stringify({
                        policy_version: '1.0',
                        action: action,
                        categories: ['strictly_necessary']
                    })
                });
            } catch (_) { /* swallow */ }
            banner.remove();
        });
    });
})();
</script>
@endunless

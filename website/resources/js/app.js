import './bootstrap';

/*
 * Zegel client-side enhancements. All behaviour progressively enhances
 * already-working server-rendered HTML — nothing here is required for
 * core functionality.
 */

(function () {
    // --- Dark mode toggle --------------------------------------------------
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    const stored = localStorage.getItem('zg-theme');
    if (stored === 'dark' || (!stored && prefersDark)) {
        document.documentElement.classList.add('dark');
    }
    document.addEventListener('click', (e) => {
        const t = e.target.closest('[data-theme-toggle]');
        if (!t) return;
        const isDark = document.documentElement.classList.toggle('dark');
        localStorage.setItem('zg-theme', isDark ? 'dark' : 'light');
    });

    // --- Drag-and-drop file upload enhancement ----------------------------
    document.querySelectorAll('[data-dropzone]').forEach((zone) => {
        const input = zone.querySelector('input[type="file"]');
        if (!input) return;

        ['dragenter', 'dragover'].forEach((evt) =>
            zone.addEventListener(evt, (e) => {
                e.preventDefault();
                zone.classList.add('ring-2', 'ring-sky-500');
            })
        );
        ['dragleave', 'drop'].forEach((evt) =>
            zone.addEventListener(evt, (e) => {
                e.preventDefault();
                zone.classList.remove('ring-2', 'ring-sky-500');
            })
        );
        zone.addEventListener('drop', (e) => {
            if (e.dataTransfer && e.dataTransfer.files.length) {
                input.files = e.dataTransfer.files;
                input.dispatchEvent(new Event('change'));
            }
        });

        input.addEventListener('change', () => {
            const file = input.files && input.files[0];
            if (!file) return;
            const label = zone.querySelector('[data-dropzone-label]');
            if (label) {
                label.textContent = `${file.name} · ${(file.size / 1024).toFixed(1)} KiB`;
            }
            // Client-side size check (server still validates).
            const maxMb = parseInt(zone.dataset.maxMb || '25', 10);
            if (file.size > maxMb * 1024 * 1024) {
                alert(`File larger than ${maxMb} MB — please choose a smaller file.`);
                input.value = '';
            }
        });
    });

    // --- Copy-to-clipboard -------------------------------------------------
    document.addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-copy-target]');
        if (!btn) return;
        const sel = btn.getAttribute('data-copy-target');
        const node = document.querySelector(sel);
        if (!node) return;
        const text = node.value ?? node.textContent ?? '';
        try { await navigator.clipboard.writeText(text); }
        catch (_) {
            node.select && node.select();
            document.execCommand('copy');
        }
        const original = btn.textContent;
        btn.textContent = 'Copied ✓';
        setTimeout(() => (btn.textContent = original), 1500);
    });

    // --- Auto-dismiss flash messages --------------------------------------
    document.querySelectorAll('[data-flash-auto]').forEach((el) => {
        setTimeout(() => {
            el.style.transition = 'opacity .5s ease-out';
            el.style.opacity = '0';
            setTimeout(() => el.remove(), 600);
        }, 5000);
    });
})();

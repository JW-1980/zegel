@extends('layouts.app')

@section('content')
<article class="prose prose-slate mx-auto max-w-3xl dark:prose-invert">
    <h1>Privacy policy</h1>
    <p class="text-sm text-slate-500">Last updated: {{ date('F j, Y') }}. Policy version 1.0.</p>

    <p>This policy explains what personal data Zegel collects, how we use it, and what rights you have under the EU General Data Protection Regulation (GDPR).</p>

    <h2>Data controller</h2>
    <p>The operator of this installation (“we”, “us”) is the data controller for all personal data processed on this site. The contact email is available on the <a href="{{ route('legal.imprint') }}">imprint page</a>.</p>

    <h2>What we collect</h2>
    <ul>
        <li><strong>Account data:</strong> name, email, hashed password, locale, timezone.</li>
        <li><strong>Usage data:</strong> login history, audit log of authenticated actions, anonymised request logs.</li>
        <li><strong>File metadata:</strong> titles, descriptions, filenames, visibility, Merkle roots and certificate data of the Zegel containers you upload.</li>
        <li><strong>Download counters:</strong> a salted HMAC fingerprint of (IP, user agent, language, encoding) — never the raw values.</li>
    </ul>

    <h2>Legal bases (Art. 6 GDPR)</h2>
    <ul>
        <li>Performance of contract — to provide your account and the file-sealing service.</li>
        <li>Legitimate interest — abuse prevention, security monitoring, aggregated analytics.</li>
        <li>Consent — for any optional cookies beyond strictly-necessary session cookies.</li>
    </ul>

    <h2>Cookies</h2>
    <p>Only strictly-necessary cookies (<code>zegel_session</code>, <code>XSRF-TOKEN</code>) are set by default. Analytics and marketing cookies are disabled. See our <a href="{{ route('legal.cookies') }}">Cookie Policy</a>.</p>

    <h2>Retention</h2>
    <p>Account data is kept until you erase your account. Audit logs are kept for 180 days. Download fingerprints are automatically rotated after 24 hours.</p>

    <h2>Your rights</h2>
    <p>Under GDPR you have the right to access (Art. 15), rectify (Art. 16), erase (Art. 17), restrict processing (Art. 18), data portability (Art. 20), and object (Art. 21). You can exercise access and erasure rights directly from your account:</p>
    @auth
        <div class="not-prose mt-4 flex flex-wrap gap-3">
            <a href="{{ route('gdpr.export') }}" class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow hover:bg-sky-500">Download my data (JSON)</a>
            <form method="POST" action="{{ route('gdpr.erase') }}"
                  onsubmit="return confirm('This will delete your account and all associated files. Are you sure?');">
                @csrf
                <input type="hidden" name="confirmation" value="DELETE-MY-ACCOUNT" />
                <button type="submit" class="rounded-md border border-rose-300 px-4 py-2 text-sm font-semibold text-rose-700 hover:bg-rose-50 dark:border-rose-900 dark:text-rose-300 dark:hover:bg-rose-900/30">Erase my account</button>
            </form>
        </div>
    @endauth

    <h2>International transfers</h2>
    <p>Unless you have explicitly configured otherwise, data is stored on the server running this installation. We do not transfer personal data to third parties.</p>

    <h2>Contact &amp; complaints</h2>
    <p>If you are unhappy with how we handle your data, you can contact the data controller or file a complaint with your local supervisory authority.</p>
</article>
@endsection

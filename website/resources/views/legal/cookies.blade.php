@extends('layouts.app')

@section('content')
<article class="prose prose-slate mx-auto max-w-3xl dark:prose-invert">
    <h1>Cookie policy</h1>
    <p>This installation only sets strictly-necessary cookies:</p>
    <ul>
        <li><code>zegel_session</code> — your login session (HTTP-only, Secure, SameSite=Lax).</li>
        <li><code>XSRF-TOKEN</code> — CSRF protection (HTTP-only, SameSite=Lax).</li>
        <li><code>zg_consent</code> — remembers your cookie-banner choice.</li>
    </ul>
    <p>No analytics, advertising, or third-party cookies are set. You can clear cookies at any time via your browser.</p>
</article>
@endsection

@extends('layouts.app')

@section('content')
<article class="prose prose-slate mx-auto max-w-3xl dark:prose-invert">
    <h1>Terms of service</h1>
    <p class="text-sm text-slate-500">Last updated: {{ date('F j, Y') }}.</p>

    <h2>Acceptable use</h2>
    <p>By using Zegel you agree not to upload illegal content, spam, malware, or any material that infringes third-party rights. You retain all intellectual property rights to the files you upload.</p>

    <h2>Service availability</h2>
    <p>Zegel is provided on an “as-is” basis without warranty of any kind. We make reasonable efforts to maintain availability but do not guarantee 100% uptime.</p>

    <h2>Limitation of liability</h2>
    <p>To the maximum extent permitted by law, Zegel and its operators are not liable for indirect, incidental or consequential damages arising out of use of the service.</p>

    <h2>Account termination</h2>
    <p>We may suspend or terminate accounts that violate these terms. You may close your account at any time via the privacy page.</p>

    <h2>Changes to these terms</h2>
    <p>We may update these terms from time to time. Material changes will be announced on the homepage or via email.</p>
</article>
@endsection

@extends('layouts.app')

@section('content')
<article class="prose prose-slate mx-auto max-w-3xl dark:prose-invert">
    <h1>Imprint</h1>
    <p>Operator: {{ \App\Models\SiteSetting::getValue('site_name', 'Zegel') }}</p>
    <p>Contact: {{ \App\Models\SiteSetting::getValue('contact_email', 'hello@example.com') }}</p>
    <p>This site runs an open-source Laravel installation of the Zegel project. Source code: <a href="https://github.com/jw-1980/zegel">github.com/jw-1980/zegel</a>.</p>
</article>
@endsection

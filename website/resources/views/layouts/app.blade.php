<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}" class="h-full">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="color-scheme" content="light dark">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <meta name="description" content="{{ $metaDescription ?? 'Zegel is an open-source tamper-proof file sealing format with a built-in certificate service.' }}">
    <meta name="theme-color" content="#0b1120">
    <meta name="robots" content="{{ $metaRobots ?? 'index,follow' }}">
    <meta name="author" content="{{ \App\Models\SiteSetting::getValue('site_name', 'Zegel') }}">
    <link rel="canonical" href="{{ url()->current() }}">
    <link rel="icon" href="{{ asset('favicon.svg') }}" type="image/svg+xml">
    <link rel="apple-touch-icon" href="{{ asset('favicon.svg') }}">
    <link rel="manifest" href="{{ url('/manifest.webmanifest') }}">
    <link rel="alternate" type="application/rss+xml" title="Zegel public releases" href="{{ url('/sitemap.xml') }}">

    <meta property="og:site_name" content="{{ \App\Models\SiteSetting::getValue('site_name', 'Zegel') }}">
    <meta property="og:title" content="{{ $title ?? config('app.name') }}">
    <meta property="og:description" content="{{ $metaDescription ?? 'Tamper-proof file sealing & verifiable certificates.' }}">
    <meta property="og:type" content="website">
    <meta property="og:url" content="{{ url()->current() }}">
    <meta property="og:image" content="{{ asset('favicon.svg') }}">
    <meta name="twitter:card" content="summary">
    <meta name="twitter:title" content="{{ $title ?? config('app.name') }}">
    <meta name="twitter:description" content="{{ $metaDescription ?? 'Tamper-proof file sealing & verifiable certificates.' }}">

    <title>{{ $title ?? (\App\Models\SiteSetting::getValue('site_name', config('app.name'))) }}</title>

    {{-- Fonts are served from the bundled Tailwind CSS using system font stacks; no external font CDN is required. --}}

    @vite(['resources/css/app.css', 'resources/js/app.js'])

    <script type="application/ld+json" nonce="{{ request()->attributes->get('csp_nonce') }}">
    @php
        $jsonLd = [
            '@context'    => 'https://schema.org',
            '@type'       => 'WebSite',
            'name'        => \App\Models\SiteSetting::getValue('site_name', 'Zegel'),
            'url'         => url('/'),
            'description' => 'Tamper-proof file sealing with verifiable certificates',
            'publisher'   => [
                '@type' => 'Organization',
                'name'  => \App\Models\SiteSetting::getValue('certificate_issuer_o', 'Zegel Trust Services'),
            ],
        ];
    @endphp
    {!! json_encode($jsonLd, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) !!}
    </script>

    @stack('head')
</head>
<body class="min-h-full bg-slate-50 text-slate-900 antialiased dark:bg-slate-950 dark:text-slate-100">
    <a href="#main" class="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded focus:bg-white focus:px-3 focus:py-2 focus:text-slate-900 focus:shadow">Skip to content</a>

    @include('partials.navbar')

    <main id="main" class="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        @include('partials.flash')
        @yield('content')
        {{ $slot ?? '' }}
    </main>

    @include('partials.footer')
    @include('partials.cookie-banner')

    @stack('scripts')
</body>
</html>

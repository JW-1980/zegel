@props(['items' => []])
@if(!empty($items))
<nav aria-label="Breadcrumb" class="mb-4 text-xs text-slate-500 dark:text-slate-400">
    <ol class="flex flex-wrap items-center gap-1">
        @foreach($items as $i => $item)
            <li class="flex items-center">
                @if(!$loop->last && !empty($item['url']))
                    <a href="{{ $item['url'] }}" class="hover:text-sky-600">{{ $item['label'] }}</a>
                @else
                    <span aria-current="page" class="font-medium text-slate-700 dark:text-slate-200">{{ $item['label'] }}</span>
                @endif
                @unless($loop->last)
                    <span class="mx-1 text-slate-400">/</span>
                @endunless
            </li>
        @endforeach
    </ol>
    <script type="application/ld+json" nonce="{{ request()->attributes->get('csp_nonce') }}">
    @php
        $list = [];
        foreach ($items as $i => $item) {
            $list[] = [
                '@type'    => 'ListItem',
                'position' => $i + 1,
                'name'     => $item['label'],
                'item'     => $item['url'] ?? url()->current(),
            ];
        }
    @endphp
    {!! json_encode(['@context' => 'https://schema.org', '@type' => 'BreadcrumbList', 'itemListElement' => $list], JSON_UNESCAPED_SLASHES) !!}
    </script>
</nav>
@endif

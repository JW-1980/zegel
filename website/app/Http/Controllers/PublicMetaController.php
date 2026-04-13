<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\ZegelFile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;

/**
 * Standard metadata / discoverability endpoints: robots.txt, security.txt,
 * humans.txt, sitemap.xml, web manifest, favicon, openapi.json.
 */
class PublicMetaController extends Controller
{
    public function robots(): Response
    {
        $body = "User-agent: *\n"
              . "Allow: /\n"
              . "Disallow: /admin\n"
              . "Disallow: /install\n"
              . "Disallow: /dashboard\n"
              . "Disallow: /files\n"
              . "Sitemap: " . url('/sitemap.xml') . "\n";
        return response($body, 200, ['Content-Type' => 'text/plain']);
    }

    public function security(): Response
    {
        $contact = (string) \App\Models\SiteSetting::getValue('contact_email', 'security@zegel.invalid');
        $body = "Contact: mailto:" . $contact . "\n"
              . "Expires: " . now()->addYear()->toIso8601String() . "\n"
              . "Preferred-Languages: en\n"
              . "Canonical: " . url('/.well-known/security.txt') . "\n"
              . "Policy: " . url('/legal/privacy') . "\n";
        return response($body, 200, ['Content-Type' => 'text/plain']);
    }

    public function humans(): Response
    {
        $body = "/* TEAM */\n"
              . "  Project:  Zegel (open-source tamper-proof file format)\n"
              . "  Source:   https://github.com/jw-1980/zegel\n\n"
              . "/* THANKS */\n"
              . "  Everyone who has contributed to Dart, PHP and Flutter open source.\n\n"
              . "/* SITE */\n"
              . "  Last update: " . now()->toDateString() . "\n"
              . "  Standards: HTML5, CSS3, PHP 8.4, Tailwind CSS 4\n"
              . "  Components: Laravel 12, MariaDB, Nginx\n";
        return response($body, 200, ['Content-Type' => 'text/plain']);
    }

    public function sitemap(): Response
    {
        $urls = collect([
            ['loc' => url('/'),                    'priority' => '1.0'],
            ['loc' => url('/downloads'),           'priority' => '0.8'],
            ['loc' => url('/legal/privacy'),       'priority' => '0.5'],
            ['loc' => url('/legal/terms'),         'priority' => '0.5'],
            ['loc' => url('/legal/cookies'),       'priority' => '0.4'],
            ['loc' => url('/legal/dpa'),           'priority' => '0.3'],
            ['loc' => url('/legal/imprint'),       'priority' => '0.3'],
        ]);
        foreach (ZegelFile::query()->where('visibility', ZegelFile::VISIBILITY_PUBLIC)->latest('published_at')->limit(500)->get() as $f) {
            $urls->push([
                'loc'      => route('files.show', $f->public_id),
                'lastmod'  => $f->updated_at?->toIso8601String(),
                'priority' => '0.7',
            ]);
        }

        $xml  = '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
        $xml .= '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . "\n";
        foreach ($urls as $u) {
            $xml .= "  <url>\n";
            $xml .= "    <loc>" . htmlspecialchars($u['loc'], ENT_XML1) . "</loc>\n";
            if (!empty($u['lastmod'])) {
                $xml .= "    <lastmod>" . $u['lastmod'] . "</lastmod>\n";
            }
            $xml .= "    <priority>" . $u['priority'] . "</priority>\n";
            $xml .= "  </url>\n";
        }
        $xml .= '</urlset>' . "\n";
        return response($xml, 200, ['Content-Type' => 'application/xml']);
    }

    public function manifest(): JsonResponse
    {
        $manifest = [
            'name'             => (string) \App\Models\SiteSetting::getValue('site_name', 'Zegel'),
            'short_name'       => 'Zegel',
            'start_url'        => '/',
            'display'          => 'standalone',
            'background_color' => '#0b1120',
            'theme_color'      => '#0b1120',
            'description'      => 'Tamper-proof file sealing platform',
            'icons'            => [
                ['src' => url('/favicon.svg'), 'sizes' => 'any', 'type' => 'image/svg+xml'],
            ],
        ];
        return response()->json($manifest, 200, [], JSON_UNESCAPED_SLASHES);
    }

    public function openapi(): JsonResponse
    {
        $spec = [
            'openapi' => '3.0.3',
            'info' => [
                'title'   => 'Zegel public API',
                'version' => '1.0.0',
                'license' => ['name' => 'AGPL-3.0'],
            ],
            'paths' => [
                '/api/v1/files/{public_id}' => [
                    'get' => [
                        'summary'    => 'Inspect a public Zegel file',
                        'parameters' => [
                            [
                                'name'     => 'public_id',
                                'in'       => 'path',
                                'required' => true,
                                'schema'   => ['type' => 'string', 'format' => 'uuid'],
                            ],
                        ],
                        'responses' => [
                            '200' => ['description' => 'Inspection result'],
                            '404' => ['description' => 'Not found or not public'],
                        ],
                    ],
                ],
            ],
        ];
        return response()->json($spec);
    }

    public function sample(): Response
    {
        $path = storage_path('app/private/sample.zgl');
        if (!is_file($path)) {
            $key    = str_repeat("\x42", 32);
            $writer = new \App\Zegel\ZegelWriter($key);
            $sealed = $writer->seal(
                "Zegel v1.4 test vector.\n\nThis is a sample .zgl file.",
                'sample.txt',
                'text/plain',
                metadata: ['purpose' => 'end-to-end test'],
                publicMetadata: ['subject_cn' => 'Zegel sample file'],
            );
            @mkdir(dirname($path), 0775, true);
            file_put_contents($path, $sealed);
        }
        return response(file_get_contents($path), 200, [
            'Content-Type'        => 'application/x-zgl',
            'Content-Disposition' => 'attachment; filename="sample.zgl"',
        ]);
    }
}

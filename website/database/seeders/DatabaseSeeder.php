<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Models\SiteSetting;
use App\Models\User;
use App\Models\ZegelFile;
use App\Services\CertificateService;
use App\Services\InstallerService;
use App\Zegel\ZegelReader;
use App\Zegel\ZegelWriter;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        /** @var InstallerService $installer */
        $installer = app(InstallerService::class);

        // Site-wide settings
        $installer->persistSiteConfig([
            'site_name'                  => 'Zegel',
            'site_tagline'               => 'Tamper-proof file sealing',
            'contact_email'              => 'hello@zegel.test',
            'allow_public_signup'        => true,
            'require_email_verification' => false,
            'max_upload_mb'              => 25,
            'certificate_issuer_cn'      => 'Zegel Certificate Authority',
            'certificate_issuer_o'       => 'Zegel Trust Services',
        ]);

        // Super administrator
        $admin = User::query()->updateOrCreate(
            ['email' => 'admin@zegel.test'],
            [
                'name'              => 'Super Admin',
                'password'          => Hash::make('Admin!Pass123'),
                'is_admin'          => true,
                'is_super_admin'    => true,
                'is_active'         => true,
                'email_verified_at' => now(),
                'gdpr_consented_at' => now(),
            ],
        );

        // Regular demo user
        $demo = User::query()->updateOrCreate(
            ['email' => 'demo@zegel.test'],
            [
                'name'              => 'Demo User',
                'password'          => Hash::make('Demo!Pass123'),
                'is_admin'          => false,
                'is_super_admin'    => false,
                'is_active'         => true,
                'email_verified_at' => now(),
                'gdpr_consented_at' => now(),
            ],
        );

        // Mock public files sealed with the PHP Zegel library.
        if (ZegelFile::query()->count() === 0) {
            $samples = [
                [
                    'title'    => 'Annual Report FY2025',
                    'filename' => 'annual-report-fy2025.pdf',
                    'ctype'    => 'application/pdf',
                    'body'     => "Zegel Annual Report — FY2025\n\nThis is a demo sealed document.",
                    'vis'      => 'public',
                    'owner'    => $admin,
                ],
                [
                    'title'    => 'Open source license inventory',
                    'filename' => 'license-inventory.txt',
                    'ctype'    => 'text/plain',
                    'body'     => str_repeat("MIT · Apache-2.0 · BSD-3-Clause · MPL-2.0\n", 200),
                    'vis'      => 'public',
                    'owner'    => $demo,
                ],
                [
                    'title'    => 'Client invoice (private)',
                    'filename' => 'invoice-123.html',
                    'ctype'    => 'text/html',
                    'body'     => '<h1>Invoice 123</h1><p>Amount: €4200.00</p>',
                    'vis'      => 'private',
                    'owner'    => $demo,
                ],
                [
                    'title'    => 'Product launch press release',
                    'filename' => 'press-release.md',
                    'ctype'    => 'text/markdown',
                    'body'     => "# Product launch\n\nWe are excited to announce Zegel v1.4.",
                    'vis'      => 'public',
                    'owner'    => $admin,
                ],
            ];

            $reader = app(ZegelReader::class);
            $certs  = app(CertificateService::class);

            foreach ($samples as $s) {
                $key    = random_bytes(32);
                $writer = new ZegelWriter($key);
                $sealed = $writer->seal(
                    $s['body'],
                    $s['filename'],
                    $s['ctype'],
                    metadata: ['title' => $s['title'], 'author' => $s['owner']->name],
                    publicMetadata: ['issuer' => 'Zegel Trust Services', 'subject_cn' => $s['filename']],
                );

                $sha256 = hash('sha256', $sealed);
                $path   = 'zegel/' . substr($sha256, 0, 2) . '/' . $sha256 . '.zgl';
                Storage::disk('private')->put($path, $sealed);

                $ins = $reader->inspect($sealed);

                $file = ZegelFile::create([
                    'user_id'           => $s['owner']->id,
                    'title'             => $s['title'],
                    'original_filename' => $s['filename'],
                    'stored_path'       => $path,
                    'content_type'      => $ins->contentType,
                    'merkle_root_hex'   => $ins->merkleRootHex,
                    'flags'             => $ins->flags,
                    'block_count'       => $ins->blockCount,
                    'size_bytes'        => strlen($sealed),
                    'sha256_hex'        => $sha256,
                    'visibility'        => $s['vis'],
                    'published_at'      => $s['vis'] === 'public' ? now() : null,
                    'subject_cn'        => $s['filename'],
                    'issuer_cn'         => 'Zegel Certificate Authority',
                ]);

                $file->forceFill(['certificate_data' => $certs->buildCertificate($file, $ins, $s['owner'])])->save();
            }
        }

        // Flip "installed" flag last so the wizard redirects correctly.
        SiteSetting::setValue(InstallerService::SCHEMA_SETTING, now()->toIso8601String(), 'string', 'Timestamp of wizard completion');
        @file_put_contents(storage_path('app/' . InstallerService::LOCK_FILE), now()->toIso8601String());
    }
}

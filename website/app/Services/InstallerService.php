<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\SiteSetting;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;

/**
 * Encapsulates all install-wizard logic so controllers stay thin and
 * installation state can be cheaply queried from middleware.
 */
class InstallerService
{
    public const LOCK_FILE = 'installed.lock';
    public const SCHEMA_SETTING = 'installed_at';

    public function isInstalled(): bool
    {
        // Fast path: lock file exists inside storage/app.
        if (is_file(storage_path('app/' . self::LOCK_FILE))) {
            return true;
        }

        try {
            if (!Schema::hasTable('site_settings')) {
                return false;
            }
            return SiteSetting::query()->where('key', self::SCHEMA_SETTING)->exists();
        } catch (\Throwable) {
            return false;
        }
    }

    public function runMigrations(): void
    {
        \Artisan::call('migrate', ['--force' => true]);
    }

    public function createSuperAdmin(array $data): User
    {
        return DB::transaction(function () use ($data) {
            $user = User::create([
                'name'               => $data['name'],
                'email'              => $data['email'],
                'password'           => Hash::make($data['password']),
                'is_admin'           => true,
                'is_super_admin'     => true,
                'is_active'          => true,
                'email_verified_at'  => now(),
                'gdpr_consented_at'  => now(),
            ]);
            return $user;
        });
    }

    public function persistSiteConfig(array $data): void
    {
        SiteSetting::setValue('site_name', $data['site_name'] ?? 'Zegel', 'string', 'Site display name');
        SiteSetting::setValue('site_tagline', $data['site_tagline'] ?? 'Tamper-proof file sealing', 'string');
        SiteSetting::setValue('contact_email', $data['contact_email'] ?? '', 'string');
        SiteSetting::setValue('allow_public_signup', (bool)($data['allow_public_signup'] ?? true), 'bool');
        SiteSetting::setValue('require_email_verification', (bool)($data['require_email_verification'] ?? false), 'bool');
        SiteSetting::setValue('max_upload_mb', (int)($data['max_upload_mb'] ?? 25), 'int');
        SiteSetting::setValue('certificate_issuer_cn', $data['certificate_issuer_cn'] ?? 'Zegel Certificate Authority', 'string');
        SiteSetting::setValue('certificate_issuer_o', $data['certificate_issuer_o'] ?? 'Zegel Trust Services', 'string');
        SiteSetting::setValue('gdpr_policy_version', '1.0', 'string');
        SiteSetting::setValue('cookie_consent_version', '1.0', 'string');
        SiteSetting::setValue('download_counter_salt', bin2hex(random_bytes(32)), 'string', 'Pepper for download fingerprints');
    }

    public function markInstalled(): void
    {
        SiteSetting::setValue(self::SCHEMA_SETTING, now()->toIso8601String(), 'string', 'Timestamp of wizard completion');
        @file_put_contents(storage_path('app/' . self::LOCK_FILE), now()->toIso8601String());
    }

    /**
     * Unique, reversible environment checks used by the wizard.
     *
     * @return array<string, array{label:string, ok:bool, detail:string}>
     */
    public function environmentChecks(): array
    {
        $checks = [];
        $checks['php_version'] = [
            'label'  => 'PHP >= 8.2',
            'ok'     => version_compare(PHP_VERSION, '8.2.0', '>='),
            'detail' => PHP_VERSION,
        ];
        foreach (['openssl', 'mbstring', 'sodium', 'pdo_sqlite', 'json', 'zlib'] as $ext) {
            $checks['ext_' . $ext] = [
                'label'  => 'Extension: ' . $ext,
                'ok'     => extension_loaded($ext),
                'detail' => extension_loaded($ext) ? 'loaded' : 'missing',
            ];
        }
        $checks['storage_writable'] = [
            'label'  => 'storage/ writable',
            'ok'     => is_writable(storage_path()),
            'detail' => storage_path(),
        ];
        $checks['database_connection'] = $this->checkDatabase();
        return $checks;
    }

    private function checkDatabase(): array
    {
        try {
            DB::connection()->getPdo();
            return ['label' => 'Database connection', 'ok' => true, 'detail' => (string)config('database.default')];
        } catch (\Throwable $e) {
            return ['label' => 'Database connection', 'ok' => false, 'detail' => $e->getMessage()];
        }
    }
}

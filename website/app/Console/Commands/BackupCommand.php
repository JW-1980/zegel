<?php

declare(strict_types=1);

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Dumps a logical backup (MySQL dump) + storage tree to a single tar.gz.
 * Safe to run hourly; rotated by hard-capping the number of kept backups.
 */
class BackupCommand extends Command
{
    protected $signature = 'zegel:backup {--keep=7}';
    protected $description = 'Create a compressed backup of the database and uploaded files.';

    public function handle(): int
    {
        $now    = now()->format('Ymd-His');
        $outDir = storage_path('app/private/backups');
        @mkdir($outDir, 0775, true);

        $sqlPath = $outDir . '/zegel-' . $now . '.sql';
        $tarPath = $outDir . '/zegel-' . $now . '.tar.gz';

        $cfg = config('database.connections.' . config('database.default'));

        if (($cfg['driver'] ?? '') !== 'mysql') {
            $this->warn('Non-MySQL drivers are dumped via php artisan schema:dump');
            \Artisan::call('schema:dump', ['--force' => true]);
        } else {
            $cmd = sprintf(
                'mysqldump -h%s -P%s -u%s %s %s > %s',
                escapeshellarg((string)($cfg['host'] ?? '127.0.0.1')),
                escapeshellarg((string)($cfg['port'] ?? '3306')),
                escapeshellarg((string)$cfg['username']),
                $cfg['password'] ? '-p' . escapeshellarg((string) $cfg['password']) : '',
                escapeshellarg((string) $cfg['database']),
                escapeshellarg($sqlPath),
            );
            shell_exec($cmd . ' 2>&1');
        }

        $storage = storage_path('app/private');
        shell_exec(sprintf(
            'tar -czf %s -C %s . 2>&1',
            escapeshellarg($tarPath),
            escapeshellarg($storage),
        ));
        @unlink($sqlPath);

        // Rotate.
        $files = glob($outDir . '/zegel-*.tar.gz') ?: [];
        sort($files);
        $keep = max(1, (int) $this->option('keep'));
        $toDelete = array_slice($files, 0, max(0, count($files) - $keep));
        foreach ($toDelete as $f) {
            @unlink($f);
        }

        $this->info('Backup written: ' . $tarPath);
        return self::SUCCESS;
    }
}

<?php

declare(strict_types=1);

namespace App\Console\Commands;

use Illuminate\Console\Command;

/**
 * Emits a single .sql file containing CREATE TABLE statements for every model
 * that uses the {@see \App\Support\ModelSchema} trait. The output is importable
 * directly into phpMyAdmin / any MariaDB/MySQL shell.
 */
class SchemaExport extends Command
{
    protected $signature = 'schema:export {--out= : Path to write (defaults to storage/app/private/zegel-schema.sql)}';

    protected $description = 'Export every Eloquent model schema as a single MariaDB-compatible .sql file.';

    /** @var list<class-string> */
    private const MODELS = [
        \App\Models\User::class,
        \App\Models\ZegelFile::class,
        \App\Models\DownloadEvent::class,
        \App\Models\SiteSetting::class,
        \App\Models\AuditLog::class,
        \App\Models\LoginAttempt::class,
        \App\Models\ConsentEvent::class,
    ];

    public function handle(): int
    {
        $sql = "-- Zegel auto-generated schema\n"
             . "-- Generated: " . now()->toIso8601String() . "\n"
             . "-- Compatible with MariaDB >= 10.6 / MySQL >= 8.0\n\n"
             . "SET FOREIGN_KEY_CHECKS=0;\n\n";

        foreach (self::MODELS as $class) {
            if (!method_exists($class, 'toSql')) {
                $this->warn($class . ' does not use the ModelSchema trait; skipped.');
                continue;
            }
            $sql .= "-- " . $class . "\n";
            $sql .= $class::toSql() . "\n";
        }

        $sql .= "SET FOREIGN_KEY_CHECKS=1;\n";

        $out = $this->option('out') ?: storage_path('app/private/zegel-schema.sql');
        @mkdir(dirname($out), 0775, true);
        file_put_contents($out, $sql);

        $this->info('Wrote ' . strlen($sql) . ' bytes to ' . $out);
        return self::SUCCESS;
    }
}

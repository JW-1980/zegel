<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\ZegelFile;
use App\Zegel\ZegelReader;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

/**
 * Re-verifies a stored Zegel file by Merkle root alone (the master key
 * is NOT available server-side). Optionally re-inspects every file in
 * the DB and flags any whose stored metadata no longer matches the
 * inspected header.
 */
class ZegelVerify extends Command
{
    protected $signature = 'zegel:verify {public_id? : UUID of a single file. If omitted, all files are re-inspected.}';
    protected $description = 'Re-inspects stored Zegel files and reports anomalies.';

    public function handle(): int
    {
        $reader = new ZegelReader();
        $query  = ZegelFile::query();
        if ($arg = $this->argument('public_id')) {
            $query->where('public_id', $arg);
        }

        $total = 0; $ok = 0; $fail = 0;
        foreach ($query->cursor() as $file) {
            $total++;
            $bytes = Storage::disk('private')->get($file->stored_path);
            if ($bytes === null) {
                $fail++;
                $this->error($file->public_id . ' · missing from disk');
                continue;
            }
            try {
                $ins = $reader->inspect($bytes);
                if ($ins->merkleRootHex !== $file->merkle_root_hex) {
                    $fail++;
                    $this->error($file->public_id . ' · Merkle mismatch');
                    continue;
                }
                $file->forceFill(['last_verified_at' => now()])->save();
                $ok++;
                $this->line('ok ' . $file->public_id);
            } catch (\Throwable $e) {
                $fail++;
                $this->error($file->public_id . ' · ' . $e->getMessage());
            }
        }

        $this->info("Checked {$total} file(s): {$ok} ok, {$fail} failed.");
        return $fail === 0 ? self::SUCCESS : self::FAILURE;
    }
}

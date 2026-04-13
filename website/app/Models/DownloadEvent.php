<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\ModelSchema;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DownloadEvent extends Model
{
    use ModelSchema;

    /** @return array<string, mixed> */
    public static function defineSchema(): array
    {
        return [
            'table' => 'download_events',
            'columns' => [
                'id'             => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
                'zegel_file_id'  => 'BIGINT UNSIGNED NOT NULL',
                'fingerprint'    => 'CHAR(64) NOT NULL',
                'day_bucket'     => 'DATE NOT NULL',
                'country'        => 'CHAR(2) NULL',
                'classification' => "VARCHAR(16) NOT NULL DEFAULT 'verified'",
                'trust_score'    => 'TINYINT UNSIGNED NOT NULL DEFAULT 100',
                'signals'        => 'JSON NULL',
                'created_at'     => 'TIMESTAMP NULL',
                'updated_at'     => 'TIMESTAMP NULL',
            ],
            'indexes' => [
                'UNIQUE KEY download_events_unique (zegel_file_id, fingerprint, day_bucket)',
                'KEY download_events_fingerprint_index (fingerprint)',
                'KEY download_events_day_bucket_index (day_bucket)',
            ],
            'foreign_keys' => [
                'CONSTRAINT download_events_zegel_file_id_foreign FOREIGN KEY (zegel_file_id) REFERENCES zegel_files (id) ON DELETE CASCADE',
            ],
        ];
    }

    public const CLASS_VERIFIED = 'verified';
    public const CLASS_SOFT     = 'soft';
    public const CLASS_REJECTED = 'rejected';

    protected $fillable = [
        'zegel_file_id',
        'fingerprint',
        'day_bucket',
        'country',
        'classification',
        'trust_score',
        'signals',
    ];

    protected function casts(): array
    {
        return [
            'day_bucket'  => 'date',
            'trust_score' => 'integer',
            'signals'     => 'array',
        ];
    }

    public function zegelFile(): BelongsTo
    {
        return $this->belongsTo(ZegelFile::class);
    }
}

<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\ModelSchema;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Str;

class ZegelFile extends Model
{
    use HasFactory, SoftDeletes, ModelSchema;

    /** @return array<string, mixed> */
    public static function defineSchema(): array
    {
        return [
            'table' => 'zegel_files',
            'columns' => [
                'id'                     => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
                'public_id'              => 'CHAR(36) NOT NULL',
                'user_id'                => 'BIGINT UNSIGNED NOT NULL',
                'title'                  => 'VARCHAR(255) NOT NULL',
                'slug'                   => 'VARCHAR(255) NULL',
                'description'            => 'TEXT NULL',
                'original_filename'      => 'VARCHAR(255) NOT NULL',
                'stored_path'            => 'VARCHAR(512) NOT NULL',
                'content_type'           => 'VARCHAR(128) NULL',
                'merkle_root_hex'        => 'CHAR(64) NOT NULL',
                'flags'                  => 'INT UNSIGNED NOT NULL DEFAULT 0',
                'block_count'            => 'INT UNSIGNED NOT NULL DEFAULT 0',
                'size_bytes'             => 'BIGINT UNSIGNED NOT NULL DEFAULT 0',
                'sha256_hex'             => 'CHAR(64) NULL',
                'visibility'             => "VARCHAR(16) NOT NULL DEFAULT 'private'",
                'published_at'           => 'TIMESTAMP NULL',
                'expires_at'             => 'TIMESTAMP NULL',
                'certificate_serial'     => 'VARCHAR(64) NOT NULL',
                'issuer_cn'              => 'VARCHAR(255) NULL',
                'subject_cn'             => 'VARCHAR(255) NULL',
                'certificate_data'       => 'JSON NULL',
                'view_count'             => 'BIGINT UNSIGNED NOT NULL DEFAULT 0',
                'download_count'         => 'BIGINT UNSIGNED NOT NULL DEFAULT 0',
                'unique_download_count'  => 'BIGINT UNSIGNED NOT NULL DEFAULT 0',
                'locked'                 => 'TINYINT(1) NOT NULL DEFAULT 0',
                'created_at'             => 'TIMESTAMP NULL',
                'updated_at'             => 'TIMESTAMP NULL',
                'deleted_at'             => 'TIMESTAMP NULL',
            ],
            'indexes' => [
                'UNIQUE KEY zegel_files_public_id_unique (public_id)',
                'UNIQUE KEY zegel_files_certificate_serial_unique (certificate_serial)',
                'KEY zegel_files_slug_index (slug)',
                'KEY zegel_files_merkle_root_hex_index (merkle_root_hex)',
                'KEY zegel_files_sha256_hex_index (sha256_hex)',
                'KEY zegel_files_visibility_published_at_index (visibility, published_at)',
                'KEY zegel_files_user_id_visibility_index (user_id, visibility)',
            ],
            'foreign_keys' => [
                'CONSTRAINT zegel_files_user_id_foreign FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE',
            ],
        ];
    }

    public const VISIBILITY_PRIVATE  = 'private';
    public const VISIBILITY_PUBLIC   = 'public';
    public const VISIBILITY_UNLISTED = 'unlisted';

    protected $fillable = [
        'public_id',
        'user_id',
        'title',
        'slug',
        'description',
        'original_filename',
        'stored_path',
        'content_type',
        'merkle_root_hex',
        'flags',
        'block_count',
        'size_bytes',
        'sha256_hex',
        'visibility',
        'published_at',
        'expires_at',
        'certificate_serial',
        'issuer_cn',
        'subject_cn',
        'certificate_data',
        'locked',
    ];

    protected function casts(): array
    {
        return [
            'certificate_data'       => 'array',
            'published_at'           => 'datetime',
            'expires_at'             => 'datetime',
            'flags'                  => 'integer',
            'block_count'            => 'integer',
            'size_bytes'             => 'integer',
            'view_count'             => 'integer',
            'download_count'         => 'integer',
            'unique_download_count'  => 'integer',
            'locked'                 => 'boolean',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (self $f): void {
            if (empty($f->public_id)) {
                $f->public_id = (string) Str::uuid();
            }
            if (empty($f->slug)) {
                $f->slug = Str::slug((string)$f->title) ?: Str::lower(Str::random(8));
            }
            if (empty($f->certificate_serial)) {
                // 16 bytes of cryptographic randomness, hex-encoded.
                $f->certificate_serial = strtoupper(bin2hex(random_bytes(16)));
            }
        });
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function downloadEvents(): HasMany
    {
        return $this->hasMany(DownloadEvent::class);
    }

    public function isPublic(): bool
    {
        return $this->visibility === self::VISIBILITY_PUBLIC;
    }

    public function isUnlisted(): bool
    {
        return $this->visibility === self::VISIBILITY_UNLISTED;
    }

    public function isPrivate(): bool
    {
        return $this->visibility === self::VISIBILITY_PRIVATE;
    }

    public function scopeVisibleTo(Builder $query, ?User $user): Builder
    {
        if ($user && $user->isAdmin()) {
            return $query; // admins see everything
        }

        return $query->where(function (Builder $q) use ($user): void {
            $q->where('visibility', self::VISIBILITY_PUBLIC);
            if ($user) {
                $q->orWhere('user_id', $user->getKey());
            }
        });
    }

    public function getRouteKeyName(): string
    {
        return 'public_id';
    }
}

<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\ModelSchema;
use Illuminate\Database\Eloquent\Model;

class AuditLog extends Model
{
    use ModelSchema;

    /** @return array<string, mixed> */
    public static function defineSchema(): array
    {
        return [
            'table' => 'audit_logs',
            'columns' => [
                'id'           => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
                'user_id'      => 'BIGINT UNSIGNED NULL',
                'event'        => 'VARCHAR(64) NOT NULL',
                'ip_address'   => 'VARCHAR(45) NULL',
                'user_agent'   => 'TEXT NULL',
                'subject_type' => 'VARCHAR(64) NULL',
                'subject_id'   => 'BIGINT UNSIGNED NULL',
                'context'      => 'JSON NULL',
                'hash_chain'   => 'CHAR(64) NULL',
                'created_at'   => 'TIMESTAMP NULL',
                'updated_at'   => 'TIMESTAMP NULL',
            ],
            'indexes' => [
                'KEY audit_logs_event_index (event)',
                'KEY audit_logs_subject_type_subject_id_index (subject_type, subject_id)',
            ],
            'foreign_keys' => [
                'CONSTRAINT audit_logs_user_id_foreign FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL',
            ],
        ];
    }

    protected $fillable = [
        'user_id',
        'event',
        'ip_address',
        'user_agent',
        'subject_type',
        'subject_id',
        'context',
        'hash_chain',
    ];

    protected function casts(): array
    {
        return [
            'context' => 'array',
        ];
    }

    public static function writeEntry(array $data): self
    {
        /** @var self|null $last */
        $last = static::query()->latest('id')->first();
        $previousChain = $last?->hash_chain ?? str_repeat('0', 64);

        $payload = [
            'event'        => $data['event'] ?? 'unknown',
            'user_id'      => $data['user_id'] ?? null,
            'ip_address'   => $data['ip_address'] ?? null,
            'user_agent'   => $data['user_agent'] ?? null,
            'subject_type' => $data['subject_type'] ?? null,
            'subject_id'   => $data['subject_id'] ?? null,
            'context'      => $data['context'] ?? null,
            'timestamp'    => now()->toIso8601String(),
        ];

        $chain = hash('sha256', $previousChain . json_encode($payload));

        return static::create(array_merge($data, ['hash_chain' => $chain]));
    }
}

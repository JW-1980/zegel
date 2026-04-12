<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\ModelSchema;
use Illuminate\Database\Eloquent\Model;

class ConsentEvent extends Model
{
    use ModelSchema;

    /** @return array<string, mixed> */
    public static function defineSchema(): array
    {
        return [
            'table' => 'consent_events',
            'columns' => [
                'id'             => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
                'user_id'        => 'BIGINT UNSIGNED NULL',
                'visitor_token'  => 'CHAR(64) NULL',
                'policy_version' => 'VARCHAR(16) NOT NULL',
                'action'         => 'VARCHAR(16) NOT NULL',
                'categories'     => 'JSON NULL',
                'ip_address'     => 'VARCHAR(45) NULL',
                'created_at'     => 'TIMESTAMP NULL',
                'updated_at'     => 'TIMESTAMP NULL',
            ],
            'indexes' => [
                'KEY consent_events_visitor_token_index (visitor_token)',
            ],
            'foreign_keys' => [
                'CONSTRAINT consent_events_user_id_foreign FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL',
            ],
        ];
    }

    protected $fillable = [
        'user_id',
        'visitor_token',
        'policy_version',
        'action',
        'categories',
        'ip_address',
    ];

    protected function casts(): array
    {
        return [
            'categories' => 'array',
        ];
    }
}

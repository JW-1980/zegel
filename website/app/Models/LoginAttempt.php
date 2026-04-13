<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\ModelSchema;
use Illuminate\Database\Eloquent\Model;

class LoginAttempt extends Model
{
    use ModelSchema;

    public $timestamps = false;

    /** @return array<string, mixed> */
    public static function defineSchema(): array
    {
        return [
            'table' => 'login_attempts',
            'columns' => [
                'id'           => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
                'email'        => 'VARCHAR(255) NOT NULL',
                'ip_address'   => 'VARCHAR(45) NOT NULL',
                'success'      => 'TINYINT(1) NOT NULL DEFAULT 0',
                'attempted_at' => 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP',
            ],
            'indexes' => [
                'KEY login_attempts_email_index (email)',
                'KEY login_attempts_email_attempted_at_index (email, attempted_at)',
                'KEY login_attempts_ip_address_attempted_at_index (ip_address, attempted_at)',
            ],
        ];
    }


    protected $fillable = ['email', 'ip_address', 'success', 'attempted_at'];

    protected function casts(): array
    {
        return [
            'success'      => 'boolean',
            'attempted_at' => 'datetime',
        ];
    }
}

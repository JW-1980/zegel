<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\ModelSchema;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    use HasFactory, Notifiable, SoftDeletes, ModelSchema;

    /** @return array<string, mixed> */
    public static function defineSchema(): array
    {
        return [
            'table' => 'users',
            'columns' => [
                'id'                 => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
                'name'               => 'VARCHAR(255) NOT NULL',
                'email'              => 'VARCHAR(255) NOT NULL',
                'email_verified_at'  => 'TIMESTAMP NULL',
                'password'           => 'VARCHAR(255) NOT NULL',
                'is_admin'           => 'TINYINT(1) NOT NULL DEFAULT 0',
                'is_super_admin'     => 'TINYINT(1) NOT NULL DEFAULT 0',
                'is_active'          => 'TINYINT(1) NOT NULL DEFAULT 1',
                'locale'             => 'VARCHAR(8) NOT NULL DEFAULT \'en\'',
                'timezone'           => 'VARCHAR(64) NOT NULL DEFAULT \'UTC\'',
                'last_login_at'      => 'TIMESTAMP NULL',
                'last_login_ip'      => 'VARCHAR(45) NULL',
                'failed_login_count' => 'INT UNSIGNED NOT NULL DEFAULT 0',
                'locked_until'       => 'TIMESTAMP NULL',
                'gdpr_consented_at'  => 'TIMESTAMP NULL',
                'remember_token'     => 'VARCHAR(100) NULL',
                'created_at'         => 'TIMESTAMP NULL',
                'updated_at'         => 'TIMESTAMP NULL',
                'deleted_at'         => 'TIMESTAMP NULL',
            ],
            'indexes' => [
                'UNIQUE KEY users_email_unique (email)',
                'KEY users_is_admin_index (is_admin)',
                'KEY users_is_super_admin_index (is_super_admin)',
                'KEY users_is_active_index (is_active)',
            ],
        ];
    }

    /** @var list<string> */
    protected $fillable = [
        'name',
        'email',
        'password',
        'is_admin',
        'is_super_admin',
        'is_active',
        'locale',
        'timezone',
        'gdpr_consented_at',
    ];

    /** @var list<string> */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at'   => 'datetime',
            'gdpr_consented_at'   => 'datetime',
            'last_login_at'       => 'datetime',
            'locked_until'        => 'datetime',
            'password'            => 'hashed',
            'is_admin'            => 'boolean',
            'is_super_admin'      => 'boolean',
            'is_active'           => 'boolean',
        ];
    }

    public function zegelFiles(): HasMany
    {
        return $this->hasMany(ZegelFile::class);
    }

    public function isAdmin(): bool
    {
        return (bool)($this->is_admin || $this->is_super_admin);
    }

    public function isSuperAdmin(): bool
    {
        return (bool)$this->is_super_admin;
    }

    public function isLocked(): bool
    {
        return $this->locked_until !== null && $this->locked_until->isFuture();
    }
}

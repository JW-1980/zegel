<?php

declare(strict_types=1);

namespace App\Models;

use App\Support\ModelSchema;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

class SiteSetting extends Model
{
    use ModelSchema;

    protected $fillable = ['key', 'value', 'type', 'description'];

    /** @return array<string, mixed> */
    public static function defineSchema(): array
    {
        return [
            'table' => 'site_settings',
            'columns' => [
                'id'          => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
                'key'         => 'VARCHAR(255) NOT NULL',
                'value'       => 'TEXT NULL',
                'type'        => "VARCHAR(16) NOT NULL DEFAULT 'string'",
                'description' => 'TEXT NULL',
                'created_at'  => 'TIMESTAMP NULL',
                'updated_at'  => 'TIMESTAMP NULL',
            ],
            'indexes' => [
                'UNIQUE KEY site_settings_key_unique (`key`)',
            ],
        ];
    }

    public static function getValue(string $key, mixed $default = null): mixed
    {
        return Cache::remember('site_setting:' . $key, 300, function () use ($key, $default) {
            $row = static::query()->where('key', $key)->first();
            if (!$row) {
                return $default;
            }
            return match ($row->type) {
                'int'  => (int)$row->value,
                'bool' => filter_var($row->value, FILTER_VALIDATE_BOOL),
                'json' => json_decode((string)$row->value, true),
                default => $row->value,
            };
        });
    }

    public static function setValue(string $key, mixed $value, string $type = 'string', ?string $description = null): void
    {
        $encoded = match ($type) {
            'bool' => $value ? '1' : '0',
            'int'  => (string)(int)$value,
            'json' => (string)json_encode($value),
            default => (string)$value,
        };
        static::query()->updateOrCreate(
            ['key' => $key],
            ['value' => $encoded, 'type' => $type, 'description' => $description],
        );
        Cache::forget('site_setting:' . $key);
    }
}

<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Trait used by Zegel models to declare their MariaDB-compatible schema in a
 * format that can be emitted to a single .sql file. This is a defensive mirror
 * of the migrations — if a migration changes, the defineSchema() method must
 * be updated to keep the two in lock-step.
 *
 * A model with this trait must implement a static defineSchema() method that
 * returns a schema array in the following format:
 *
 *   [
 *     'table'   => 'users',
 *     'columns' => [
 *       'id'       => 'BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY',
 *       'email'    => 'VARCHAR(255) NOT NULL',
 *       ...
 *     ],
 *     'indexes' => [
 *       'UNIQUE KEY users_email_unique (email)',
 *       ...
 *     ],
 *     'engine'  => 'InnoDB',
 *   ];
 */
trait ModelSchema
{
    /**
     * Emit a MariaDB CREATE TABLE statement for this model.
     */
    public static function toSql(): string
    {
        $schema = static::defineSchema();
        $lines  = [];

        foreach ($schema['columns'] as $name => $definition) {
            $lines[] = '  `' . $name . '` ' . $definition;
        }
        foreach ($schema['indexes'] ?? [] as $idx) {
            $lines[] = '  ' . $idx;
        }
        foreach ($schema['foreign_keys'] ?? [] as $fk) {
            $lines[] = '  ' . $fk;
        }

        $engine  = $schema['engine']  ?? 'InnoDB';
        $charset = $schema['charset'] ?? 'utf8mb4';
        $collate = $schema['collate'] ?? 'utf8mb4_unicode_ci';

        return "CREATE TABLE IF NOT EXISTS `{$schema['table']}` (\n"
            . implode(",\n", $lines)
            . "\n) ENGINE={$engine} DEFAULT CHARSET={$charset} COLLATE={$collate};\n";
    }
}

<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * Result of a successful verify() call.
 */
final class ZegelResult
{
    public function __construct(
        public readonly bool $valid,
        public readonly string $content,
        /** @var array<string,mixed>|null */
        public readonly ?array $metadata,
        public readonly ?string $filename,
        public readonly ?string $contentType,
        /** @var array<string,mixed>|null */
        public readonly ?array $publicMetadata,
        public readonly string $merkleRootHex,
        public readonly int $flags,
        public readonly int $versionMajor,
        public readonly int $versionMinor,
        public readonly int $timestamp,
        public readonly int $blockCount,
    ) {}
}

<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * Header-only inspection result (no master key required).
 */
final class ZegelInspection
{
    public function __construct(
        public readonly int $versionMajor,
        public readonly int $versionMinor,
        public readonly int $flags,
        public readonly int $timestamp,
        public readonly ?string $contentType,
        public readonly ?string $filename,
        public readonly int $blockCount,
        /** @var array<string,mixed>|null */
        public readonly ?array $publicMetadata,
        public readonly ?int $expirationTimestamp,
        public readonly string $merkleRootHex,
    ) {}

    public function versionString(): string
    {
        return $this->versionMajor . '.' . $this->versionMinor;
    }
}

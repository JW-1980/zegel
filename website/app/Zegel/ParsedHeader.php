<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * Internal parsed-header container used by {@see ZegelReader}.
 *
 * This is a plain mutable DTO – it is not part of the public API.
 */
final class ParsedHeader
{
    public int $versionMajor = 0;
    public int $versionMinor = 0;
    public int $flags = 0;
    public int $timestamp = 0;
    public string $contentType = '';
    public string $filename = '';
    public string $salt = '';
    public int $blockCount = 0;
    public ?int $expirationTimestamp = null;
    /** @var array<string,mixed>|null */
    public ?array $publicMetadata = null;
    /** @var list<array{type:int, hash:string, ciphertextLen:int, iv:string, tag:string}> */
    public array $directory = [];
    public string $merkleRoot = '';
    public ?string $keyCommitment = null;
    public int $dataStart = 0;
}

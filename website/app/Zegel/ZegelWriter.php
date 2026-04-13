<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * Builds v1.4 Zegel files.
 *
 * Supported flags:
 *   - HAS_METADATA        (encrypted JSON metadata as block 0)
 *   - COMPRESSED          (zlib-level 6 before encryption)
 *   - HAS_KEY_COMMITMENT  (key commitment hash after Merkle root)
 *   - HAS_EXPIRATION      (expiration baked into HKDF info)
 *   - HAS_PUBLIC_METADATA (unencrypted integrity-protected metadata)
 *
 * This subset covers the web-upload use case completely. Advanced flags
 * (canary, split-key, redaction, disclosure, versioning, regulatory hold,
 * trusted timestamps) are intentionally out of scope for the website.
 */
final class ZegelWriter
{
    public function __construct(
        /** 32-byte master key. */
        private readonly string $masterKey,
        /** Optional 32-byte salt; if null, a CSPRNG salt is generated. */
        private readonly ?string $salt = null,
        /** Block size for content chunks. */
        private readonly int $blockSize = ZegelFormat::DEFAULT_BLOCK_SIZE,
    ) {
        if (strlen($this->masterKey) !== 32) {
            throw new \InvalidArgumentException('Master key must be 32 bytes');
        }
        if ($this->salt !== null && strlen($this->salt) !== ZegelFormat::SALT_SIZE) {
            throw new \InvalidArgumentException('Salt must be 32 bytes');
        }
    }

    /**
     * Seal $content into a .zgl byte string.
     *
     * @param array<string, mixed>|null $metadata        Encrypted block-0 metadata.
     * @param array<string, mixed>|null $publicMetadata  Unencrypted header metadata.
     */
    public function seal(
        string $content,
        string $filename = '',
        string $contentType = '',
        ?array $metadata = null,
        ?array $publicMetadata = null,
        bool $compress = true,
        bool $keyCommitment = true,
        ?int $expirationTimestamp = null,
    ): string {
        $salt = $this->salt ?? random_bytes(ZegelFormat::SALT_SIZE);

        // 1. Build plaintext blocks in order: [metadata?, content...].
        /** @var list<array{type:int, plaintext:string}> $plainBlocks */
        $plainBlocks = [];
        $flags = 0;

        if ($metadata !== null) {
            $flags |= ZegelFormat::FLAG_HAS_METADATA;
            $plainBlocks[] = [
                'type'      => ZegelFormat::BLOCK_METADATA,
                'plaintext' => (string)json_encode($metadata, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE),
            ];
        }

        // Split content into fixed-size chunks.
        $totalContentLength = strlen($content);
        if ($totalContentLength === 0) {
            // Zegel requires at least one block – use a single empty content block.
            $plainBlocks[] = ['type' => ZegelFormat::BLOCK_CONTENT, 'plaintext' => ''];
        } else {
            for ($offset = 0; $offset < $totalContentLength; $offset += $this->blockSize) {
                $plainBlocks[] = [
                    'type'      => ZegelFormat::BLOCK_CONTENT,
                    'plaintext' => substr($content, $offset, $this->blockSize),
                ];
            }
        }

        if ($compress) {
            $flags |= ZegelFormat::FLAG_COMPRESSED;
            foreach ($plainBlocks as $i => $b) {
                if ($b['type'] === ZegelFormat::BLOCK_CONTENT) {
                    $deflated = zlib_encode($b['plaintext'], ZLIB_ENCODING_DEFLATE, 6);
                    if ($deflated === false) {
                        throw new ZegelException('zlib_encode failed');
                    }
                    $plainBlocks[$i]['plaintext'] = $deflated;
                }
            }
        }

        if ($keyCommitment) {
            $flags |= ZegelFormat::FLAG_HAS_KEY_COMMITMENT;
        }

        $expirationDate = null;
        if ($expirationTimestamp !== null) {
            $flags |= ZegelFormat::FLAG_HAS_EXPIRATION;
            $expirationDate = gmdate('Y-m-d', $expirationTimestamp);
        }

        $publicMetadataJson = null;
        if ($publicMetadata !== null) {
            $flags |= ZegelFormat::FLAG_HAS_PUBLIC_METADATA;
            $publicMetadataJson = (string)json_encode($publicMetadata, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        }

        // 2. Compute raw leaf hashes (SHA-256 of each block plaintext-post-compression).
        $leafHashes = [];
        foreach ($plainBlocks as $b) {
            $leafHashes[] = hash('sha256', $b['plaintext'], true);
        }

        // 3. Build Merkle root (v1.4 domain-separated).
        $merkleRoot = MerkleTree::buildRoot($leafHashes);

        // 4. Derive per-block keys + hedged nonces.
        $blockKeys = [];
        $blockIvs  = [];
        foreach ($plainBlocks as $i => $_b) {
            $blockKeys[$i] = KeyDerivation::deriveBlockKey(
                $this->masterKey, $merkleRoot, $salt, $i, $expirationDate,
            );
            $blockIvs[$i] = KeyDerivation::hedgedNonce(
                $this->masterKey, $merkleRoot, $salt, $i,
            );
        }

        // 5. Encrypt blocks with AES-256-GCM + AAD binding.
        $ciphertexts = [];
        $authTags    = [];
        foreach ($plainBlocks as $i => $b) {
            $aad = pack('C', $b['type']) . pack('N', $i) . $salt;
            $tag = '';
            $ct  = openssl_encrypt(
                $b['plaintext'],
                'aes-256-gcm',
                $blockKeys[$i],
                OPENSSL_RAW_DATA,
                $blockIvs[$i],
                $tag,
                $aad,
                ZegelFormat::TAG_SIZE,
            );
            if ($ct === false) {
                throw new ZegelException('AES-GCM encryption failed: ' . openssl_error_string());
            }
            $ciphertexts[$i] = $ct;
            $authTags[$i]    = $tag;
        }

        // 6. Assemble header.
        $filenameBytes = (string)$filename;
        if (strlen($filenameBytes) > ZegelFormat::MAX_FILENAME_LENGTH) {
            throw new \InvalidArgumentException('Filename too long');
        }

        $contentTypeBytes = (string)$contentType;
        if (strlen($contentTypeBytes) > ZegelFormat::CONTENT_TYPE_SIZE) {
            throw new \InvalidArgumentException('Content-Type too long');
        }
        $contentTypePadded = str_pad($contentTypeBytes, ZegelFormat::CONTENT_TYPE_SIZE, "\x00");

        $header  = ZegelFormat::MAGIC;
        $header .= pack('C', ZegelFormat::VERSION_MAJOR);
        $header .= pack('C', ZegelFormat::VERSION_MINOR);
        $header .= pack('n', $flags);
        $header .= pack('J', time());
        $header .= $contentTypePadded;
        $header .= pack('n', strlen($filenameBytes));
        $header .= $filenameBytes;
        $header .= $salt;
        $header .= pack('N', count($plainBlocks));

        // Extended header (flag-dependent, spec-defined order).
        if ($expirationTimestamp !== null) {
            $header .= pack('J', $expirationTimestamp);
        }
        if ($publicMetadataJson !== null) {
            $header .= pack('N', strlen($publicMetadataJson));
            $header .= $publicMetadataJson;
        }

        // Block directory.
        foreach ($plainBlocks as $i => $_b) {
            $entry  = pack('C', $plainBlocks[$i]['type']);
            $entry .= $leafHashes[$i];
            $entry .= pack('N', strlen($ciphertexts[$i]));
            $entry .= $blockIvs[$i];
            $entry .= $authTags[$i];
            if (strlen($entry) !== ZegelFormat::BLOCK_DIRECTORY_ENTRY_SIZE) {
                throw new ZegelException('Directory entry size mismatch');
            }
            $header .= $entry;
        }

        // Merkle root.
        $header .= $merkleRoot;

        // Optional key commitment.
        if ($keyCommitment) {
            $header .= KeyDerivation::computeKeyCommitment($blockKeys);
        }

        // Encrypted block data.
        $body = '';
        foreach ($plainBlocks as $i => $_b) {
            $body .= $ciphertexts[$i];
        }

        $preSeal = $header . $body;

        // 7. Master seal.
        $sealKey = KeyDerivation::computeSealKey($merkleRoot, $this->masterKey, $salt);
        $seal    = KeyDerivation::computeMasterSeal($sealKey, $preSeal);

        return $preSeal . $seal;
    }
}

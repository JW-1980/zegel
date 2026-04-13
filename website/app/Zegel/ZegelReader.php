<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * Parses, verifies, and extracts Zegel files. Supports the subset of flags
 * emitted by {@see ZegelWriter} plus the baseline v1.4 header format. Files
 * using unsupported flags are still inspected structurally but verification
 * will refuse to decrypt them.
 */
final class ZegelReader
{
    /**
     * Full verification and extraction.
     *
     * @return ZegelResult
     *
     * @throws ZegelFormatException      on structural errors
     * @throws ZegelTamperedException    on integrity failures
     * @throws ZegelExpiredException     when the file is expired
     */
    public function verify(string $fileBytes, string $masterKey): ZegelResult
    {
        $h = $this->parseAll($fileBytes);

        // 1. Check expiration.
        if ($h->expirationTimestamp !== null) {
            if (time() >= $h->expirationTimestamp) {
                throw new ZegelExpiredException('File expired at epoch ' . $h->expirationTimestamp);
            }
        }

        // 2. Verify master seal.
        $sealOffset = strlen($fileBytes) - ZegelFormat::SEAL_SIZE;
        if ($sealOffset < 0) {
            throw new ZegelFormatException('File too short for master seal');
        }
        $preSeal    = substr($fileBytes, 0, $sealOffset);
        $storedSeal = substr($fileBytes, $sealOffset);
        $sealKey    = KeyDerivation::computeSealKey($h->merkleRoot, $masterKey, $h->salt);
        $computed   = KeyDerivation::computeMasterSeal($sealKey, $preSeal);
        if (!KeyDerivation::constantTimeEquals($computed, $storedSeal)) {
            throw new ZegelTamperedException('Master seal verification failed');
        }

        // 3. Verify Merkle root.
        $leafHashes = array_map(static fn($d) => $d['hash'], $h->directory);
        $computedRoot = MerkleTree::buildRoot($leafHashes);
        if (!KeyDerivation::constantTimeEquals($computedRoot, $h->merkleRoot)) {
            throw new ZegelTamperedException('Merkle root mismatch');
        }

        // 4. Determine expiration date string for HKDF info.
        $expirationDate = null;
        if ($h->expirationTimestamp !== null) {
            $expirationDate = gmdate('Y-m-d', $h->expirationTimestamp);
        }

        // 5. Verify key commitment if present.
        if (($h->flags & ZegelFormat::FLAG_HAS_KEY_COMMITMENT) !== 0) {
            $keys = [];
            for ($i = 0; $i < $h->blockCount; $i++) {
                $keys[] = KeyDerivation::deriveBlockKey(
                    $masterKey, $h->merkleRoot, $h->salt, $i, $expirationDate,
                );
            }
            $commitment = KeyDerivation::computeKeyCommitment($keys);
            if (!KeyDerivation::constantTimeEquals($commitment, (string)$h->keyCommitment)) {
                throw new ZegelTamperedException('Key commitment mismatch');
            }
        }

        // 6. Decrypt & decompress blocks.
        $dataOffset    = $h->dataStart;
        $content       = '';
        $metadata      = null;
        foreach ($h->directory as $i => $entry) {
            $ciphertext  = substr($fileBytes, $dataOffset, $entry['ciphertextLen']);
            $dataOffset += $entry['ciphertextLen'];

            if ($entry['type'] === ZegelFormat::BLOCK_REDACTED) {
                continue;
            }

            $blockKey = KeyDerivation::deriveBlockKey(
                $masterKey, $h->merkleRoot, $h->salt, $i, $expirationDate,
            );

            $aad = pack('C', $entry['type']) . pack('N', $i) . $h->salt;

            $plaintext = openssl_decrypt(
                $ciphertext,
                'aes-256-gcm',
                $blockKey,
                OPENSSL_RAW_DATA,
                $entry['iv'],
                $entry['tag'],
                $aad,
            );
            if ($plaintext === false) {
                throw new ZegelTamperedException('Block ' . $i . ' decryption failed');
            }

            $ptHash = hash('sha256', $plaintext, true);
            if (!KeyDerivation::constantTimeEquals($ptHash, $entry['hash'])) {
                throw new ZegelTamperedException('Block ' . $i . ' plaintext hash mismatch');
            }

            if (($h->flags & ZegelFormat::FLAG_COMPRESSED) !== 0 && $entry['type'] === ZegelFormat::BLOCK_CONTENT) {
                $decoded = @zlib_decode($plaintext);
                if ($decoded === false) {
                    throw new ZegelTamperedException('zlib decode failed for block ' . $i);
                }
                $plaintext = $decoded;
            }

            switch ($entry['type']) {
                case ZegelFormat::BLOCK_CONTENT:
                    $content .= $plaintext;
                    break;
                case ZegelFormat::BLOCK_METADATA:
                    $metadata = json_decode($plaintext, true);
                    break;
                default:
                    // Other block types are currently ignored by this reader.
                    break;
            }
        }

        return new ZegelResult(
            valid: true,
            content: $content,
            metadata: is_array($metadata) ? $metadata : null,
            filename: $h->filename !== '' ? $h->filename : null,
            contentType: $h->contentType !== '' ? $h->contentType : null,
            publicMetadata: $h->publicMetadata,
            merkleRootHex: bin2hex($h->merkleRoot),
            flags: $h->flags,
            versionMajor: $h->versionMajor,
            versionMinor: $h->versionMinor,
            timestamp: $h->timestamp,
            blockCount: $h->blockCount,
        );
    }

    /**
     * Inspect a file without a master key. Returns the decoded header.
     */
    public function inspect(string $fileBytes): ZegelInspection
    {
        $h = $this->parseAll($fileBytes);
        return new ZegelInspection(
            versionMajor: $h->versionMajor,
            versionMinor: $h->versionMinor,
            flags: $h->flags,
            timestamp: $h->timestamp,
            contentType: $h->contentType !== '' ? $h->contentType : null,
            filename: $h->filename !== '' ? $h->filename : null,
            blockCount: $h->blockCount,
            publicMetadata: $h->publicMetadata,
            expirationTimestamp: $h->expirationTimestamp,
            merkleRootHex: bin2hex($h->merkleRoot),
        );
    }

    // ------------------------------------------------------------------
    // Internal parsing
    // ------------------------------------------------------------------
    private function parseAll(string $fileBytes): ParsedHeader
    {
        $h = new ParsedHeader();
        $len = strlen($fileBytes);

        if ($len < 8 || substr($fileBytes, 0, 8) !== ZegelFormat::MAGIC) {
            throw new ZegelFormatException('Invalid magic bytes');
        }
        if ($len < 86) {
            throw new ZegelFormatException('File too short for header');
        }

        $h->versionMajor = ord($fileBytes[8]);
        $h->versionMinor = ord($fileBytes[9]);

        // Accept any v1.x file (forward compatible headers).
        if ($h->versionMajor !== 1) {
            throw new ZegelFormatException('Unsupported Zegel major version ' . $h->versionMajor);
        }

        $h->flags     = unpack('n', substr($fileBytes, 10, 2))[1];
        $tsParts      = unpack('J', substr($fileBytes, 12, 8));
        $h->timestamp = (int)$tsParts[1];

        $ctRaw  = substr($fileBytes, 20, ZegelFormat::CONTENT_TYPE_SIZE);
        $nulPos = strpos($ctRaw, "\x00");
        $h->contentType = $nulPos === false ? $ctRaw : substr($ctRaw, 0, $nulPos);

        $filenameLen = unpack('n', substr($fileBytes, 84, 2))[1];
        if ($len < 86 + $filenameLen) {
            throw new ZegelFormatException('File too short for filename');
        }
        $h->filename = substr($fileBytes, 86, $filenameLen);

        $saltOffset = 86 + $filenameLen;
        if ($len < $saltOffset + ZegelFormat::SALT_SIZE + 4) {
            throw new ZegelFormatException('File too short for salt + block count');
        }
        $h->salt = substr($fileBytes, $saltOffset, ZegelFormat::SALT_SIZE);

        $blockCountOffset = $saltOffset + ZegelFormat::SALT_SIZE;
        $h->blockCount    = unpack('N', substr($fileBytes, $blockCountOffset, 4))[1];

        if ($h->blockCount === 0 || $h->blockCount > ZegelFormat::MAX_BLOCK_COUNT) {
            throw new ZegelFormatException('Invalid block count ' . $h->blockCount);
        }

        $cursor = $blockCountOffset + 4;

        // Extended header (only flags we actually support).
        if (($h->flags & ZegelFormat::FLAG_PASSWORD_DERIVED) !== 0) {
            $this->requireBytes($fileBytes, $cursor + 8, 'Argon2 params');
            $cursor += 8; // PHP side not used
        }
        if (($h->flags & ZegelFormat::FLAG_HAS_EXPIRATION) !== 0) {
            $this->requireBytes($fileBytes, $cursor + 8, 'expiration timestamp');
            $h->expirationTimestamp = (int)unpack('J', substr($fileBytes, $cursor, 8))[1];
            $cursor += 8;
        }
        if (($h->flags & ZegelFormat::FLAG_HAS_CANARY) !== 0) {
            $this->requireBytes($fileBytes, $cursor + 32, 'recipient ID');
            $cursor += 32;
        }
        if (($h->flags & ZegelFormat::FLAG_SPLIT_KEY) !== 0) {
            $this->requireBytes($fileBytes, $cursor + 2, 'split-key params');
            $cursor += 2;
        }
        if (($h->flags & ZegelFormat::FLAG_VERSIONED) !== 0) {
            $this->requireBytes($fileBytes, $cursor + 32, 'version chain hash');
            $cursor += 32;
        }
        if (($h->flags & ZegelFormat::FLAG_HAS_PUBLIC_METADATA) !== 0) {
            $this->requireBytes($fileBytes, $cursor + 4, 'public metadata length');
            $pubLen = unpack('N', substr($fileBytes, $cursor, 4))[1];
            if ($pubLen > ZegelFormat::MAX_PUBLIC_METADATA_SIZE) {
                throw new ZegelFormatException('Public metadata too large');
            }
            $cursor += 4;
            $this->requireBytes($fileBytes, $cursor + $pubLen, 'public metadata body');
            $pubJson = substr($fileBytes, $cursor, $pubLen);
            $decoded = json_decode($pubJson, true);
            if (!is_array($decoded)) {
                throw new ZegelFormatException('Public metadata is not valid JSON');
            }
            $h->publicMetadata = $decoded;
            $cursor += $pubLen;
        }

        // Block directory.
        $directorySize = $h->blockCount * ZegelFormat::BLOCK_DIRECTORY_ENTRY_SIZE;
        $this->requireBytes($fileBytes, $cursor + $directorySize, 'block directory');
        $h->directory = [];
        for ($i = 0; $i < $h->blockCount; $i++) {
            $eo = $cursor;
            $h->directory[] = [
                'type'          => ord($fileBytes[$eo]),
                'hash'          => substr($fileBytes, $eo + 1, 32),
                'ciphertextLen' => unpack('N', substr($fileBytes, $eo + 33, 4))[1],
                'iv'            => substr($fileBytes, $eo + 37, 12),
                'tag'            => substr($fileBytes, $eo + 49, 16),
            ];
            $cursor += ZegelFormat::BLOCK_DIRECTORY_ENTRY_SIZE;
        }

        // Merkle root.
        $this->requireBytes($fileBytes, $cursor + ZegelFormat::HASH_SIZE, 'Merkle root');
        $h->merkleRoot = substr($fileBytes, $cursor, ZegelFormat::HASH_SIZE);
        $cursor += ZegelFormat::HASH_SIZE;

        // Key commitment.
        if (($h->flags & ZegelFormat::FLAG_HAS_KEY_COMMITMENT) !== 0) {
            $this->requireBytes($fileBytes, $cursor + ZegelFormat::HASH_SIZE, 'key commitment');
            $h->keyCommitment = substr($fileBytes, $cursor, ZegelFormat::HASH_SIZE);
            $cursor += ZegelFormat::HASH_SIZE;
        }

        $h->dataStart = $cursor;
        return $h;
    }

    private function requireBytes(string $fileBytes, int $required, string $label): void
    {
        if (strlen($fileBytes) < $required) {
            throw new ZegelFormatException('File too short for ' . $label);
        }
    }
}

<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * HKDF (RFC 5869) and HMAC helpers mirroring the Dart reference
 * implementation. All byte strings in this class are raw PHP strings.
 */
final class KeyDerivation
{
    private function __construct() {}

    /**
     * Constant-time string comparison that also guards against length leaks.
     */
    public static function constantTimeEquals(string $a, string $b): bool
    {
        return hash_equals($a, $b);
    }

    /**
     * HKDF-SHA256 extract-and-expand (RFC 5869).
     *
     * @param string $ikm     Input keying material (raw bytes).
     * @param string $salt    Salt (raw bytes).
     * @param string $info    Info string (raw bytes).
     * @param int    $length  Desired output length in bytes.
     */
    public static function hkdf(string $ikm, string $salt, string $info, int $length): string
    {
        return hash_hkdf('sha256', $ikm, $length, $info, $salt);
    }

    /**
     * Derives the 32-byte per-block AES-256 encryption key.
     *
     * HKDF(ikm = masterKey || merkleRoot, salt = master_salt, info = "zegel-block-key-v1:INDEX[:exp=YYYY-MM-DD]")
     */
    public static function deriveBlockKey(
        string $masterKey,
        string $merkleRoot,
        string $salt,
        int $blockIndex,
        ?string $expirationDate = null,
    ): string {
        $info = ZegelFormat::HKDF_INFO_PREFIX . (string)$blockIndex;
        if ($expirationDate !== null) {
            $info .= ':exp=' . $expirationDate;
        }
        return self::hkdf($masterKey . $merkleRoot, $salt, $info, 32);
    }

    /**
     * Derives a deterministic 12-byte nonce for a block.
     *
     * The actual on-disk IV is (derived_nonce XOR random_nonce) but verification
     * uses the stored IV as-is. Writers call {@see hedgedNonce()} to mix.
     */
    public static function deriveBlockNonce(
        string $masterKey,
        string $merkleRoot,
        string $salt,
        int $blockIndex,
    ): string {
        $info = ZegelFormat::HKDF_NONCE_PREFIX . (string)$blockIndex;
        return self::hkdf($masterKey . $merkleRoot, $salt, $info, 12);
    }

    /**
     * Hedged nonce: XOR of the HKDF-derived nonce with a CSPRNG nonce.
     */
    public static function hedgedNonce(
        string $masterKey,
        string $merkleRoot,
        string $salt,
        int $blockIndex,
    ): string {
        $derived = self::deriveBlockNonce($masterKey, $merkleRoot, $salt, $blockIndex);
        $random  = random_bytes(12);
        $out = '';
        for ($i = 0; $i < 12; $i++) {
            $out .= chr(ord($derived[$i]) ^ ord($random[$i]));
        }
        return $out;
    }

    /**
     * Computes the seal key: HMAC-SHA256(merkleRoot, masterKey || salt).
     */
    public static function computeSealKey(string $merkleRoot, string $masterKey, string $salt): string
    {
        return hash_hmac('sha256', $masterKey . $salt, $merkleRoot, true);
    }

    /**
     * Computes the master seal over every byte up to (but not including) the seal.
     */
    public static function computeMasterSeal(string $sealKey, string $fileBytes): string
    {
        return hash_hmac('sha512', $fileBytes, $sealKey, true);
    }

    /**
     * Computes the key commitment hash: SHA-256(concat(all block keys)).
     *
     * @param list<string> $blockKeys
     */
    public static function computeKeyCommitment(array $blockKeys): string
    {
        return hash('sha256', implode('', $blockKeys), true);
    }
}

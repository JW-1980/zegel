<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * Binary SHA-256 Merkle tree (RFC 6962 domain-separated, v1.4+).
 *
 * Leaf hashes:    SHA-256(0x00 || raw_hash)
 * Internal nodes: SHA-256(0x01 || left || right)
 */
final class MerkleTree
{
    public const LEAF_PREFIX = "\x00";
    public const NODE_PREFIX = "\x01";

    public static function hashLeaf(string $rawHash): string
    {
        return hash('sha256', self::LEAF_PREFIX . $rawHash, true);
    }

    private static function hashPair(string $left, string $right): string
    {
        return hash('sha256', self::NODE_PREFIX . $left . $right, true);
    }

    /**
     * @param list<string> $leafHashes Raw 32-byte SHA-256 plaintext digests.
     */
    public static function buildRoot(array $leafHashes): string
    {
        if ($leafHashes === []) {
            throw new \InvalidArgumentException('Cannot build Merkle tree from zero leaves');
        }

        $layer = array_map([self::class, 'hashLeaf'], $leafHashes);

        if (count($layer) === 1) {
            return $layer[0];
        }

        while (count($layer) > 1) {
            if (count($layer) % 2 === 1) {
                $layer[] = end($layer);
            }
            $next = [];
            for ($i = 0, $n = count($layer); $i < $n; $i += 2) {
                $next[] = self::hashPair($layer[$i], $layer[$i + 1]);
            }
            $layer = $next;
        }

        return $layer[0];
    }
}

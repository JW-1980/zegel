<?php

declare(strict_types=1);

namespace App\Services;

use App\Models\SiteSetting;
use App\Models\User;
use App\Models\ZegelFile;
use App\Zegel\ZegelInspection;

/**
 * Builds the JSON payload used to render a realistic-looking certificate
 * for a Zegel file. This deliberately mimics X.509 field naming conventions
 * (Issuer, Subject, Serial Number, Valid From/To, Thumbprint, Key Usage) so
 * the resulting UI is instantly recognisable as "a certificate" without
 * misrepresenting itself as a real X.509 certificate from a CA.
 */
class CertificateService
{
    /**
     * @return array<string, mixed>
     */
    public function buildCertificate(ZegelFile $file, ZegelInspection $ins, User $owner): array
    {
        $issuerCn  = SiteSetting::getValue('certificate_issuer_cn', 'Zegel Certificate Authority');
        $issuerO   = SiteSetting::getValue('certificate_issuer_o', 'Zegel Trust Services');
        $subjectCn = $file->subject_cn ?: ($ins->filename ?? $file->original_filename);

        // Thumbprint = SHA-1 of merkle root ∘ salted suffix, rendered in
        // colon-delimited hex (like a real X.509 thumbprint UI).
        $thumbprint = strtoupper(
            implode(':', str_split(hash('sha1', (string) hex2bin($file->merkle_root_hex)), 2)),
        );

        $validFrom = $file->created_at?->copy() ?? now();
        $validTo   = $file->expires_at?->copy() ?? $validFrom->copy()->addYears(5);

        return [
            'version'              => '3 (0x2)',
            'serial_number'        => $this->formatSerial($file->certificate_serial),
            'signature_algorithm'  => 'HMAC-SHA512 over ZEGEL-v1.4',
            'issuer' => [
                'common_name'        => $issuerCn,
                'organization'       => $issuerO,
                'organizational_unit'=> 'Integrity Seal Authority',
                'country'            => 'NL',
            ],
            'subject' => [
                'common_name'        => $subjectCn,
                'organization'       => $owner->name,
                'email'              => $owner->email,
                'content_type'       => $ins->contentType,
                'original_filename'  => $file->original_filename,
            ],
            'validity' => [
                'not_before' => $validFrom->toIso8601String(),
                'not_after'  => $validTo->toIso8601String(),
            ],
            'public_key_info' => [
                'algorithm' => 'AES-256-GCM + HKDF-SHA256 (Zegel block keys)',
                'key_size'  => 256,
            ],
            'extensions' => [
                'key_usage' => ['Digital Signature', 'Content Integrity Seal', 'Tamper Detection'],
                'zegel_flags' => $this->describeFlags($ins->flags),
                'zegel_block_count' => $ins->blockCount,
                'zegel_version'     => $ins->versionString(),
                'merkle_root'       => $file->merkle_root_hex,
            ],
            'fingerprints' => [
                'sha256' => $file->sha256_hex,
                'thumbprint_sha1' => $thumbprint,
            ],
            'public_metadata' => $ins->publicMetadata ?: null,
        ];
    }

    private function formatSerial(string $serial): string
    {
        return implode(':', str_split($serial, 2));
    }

    /**
     * @return list<string>
     */
    private function describeFlags(int $flags): array
    {
        $map = [
            0x0001 => 'HAS_METADATA',
            0x0002 => 'COMPRESSED',
            0x0004 => 'PASSWORD_DERIVED',
            0x0008 => 'HAS_KEY_COMMITMENT',
            0x0010 => 'HAS_EXPIRATION',
            0x0020 => 'HAS_PUBLIC_METADATA',
            0x0040 => 'MULTI_FILE',
            0x0080 => 'HAS_CANARY',
            0x0100 => 'HAS_REDACTIONS',
            0x0200 => 'SPLIT_KEY',
            0x0400 => 'SELECTIVE_DISCLOSURE',
            0x0800 => 'VERSIONED',
            0x1000 => 'REGULATORY_HOLD',
            0x2000 => 'HAS_TIMESTAMP',
            0x4000 => 'ANONYMOUS',
            0x8000 => 'HAS_CLASSIFICATION',
        ];
        $out = [];
        foreach ($map as $mask => $name) {
            if (($flags & $mask) !== 0) {
                $out[] = $name;
            }
        }
        return $out;
    }
}

<?php

declare(strict_types=1);

namespace App\Zegel;

/**
 * Binary format constants for the Zegel file format (v1.4).
 *
 * All multi-byte integers are big-endian. This class mirrors
 * {@see \lib\lib\src\format.dart} in the reference Dart implementation
 * and is the single source of truth for the PHP port.
 */
final class ZegelFormat
{
    public const MAGIC = "ZEGEL\x00\x01\x00";
    public const VERSION_MAJOR = 1;
    public const VERSION_MINOR = 4;

    public const DEFAULT_BLOCK_SIZE = 65536;

    // Flag bitmask constants (uint16).
    public const FLAG_HAS_METADATA         = 0x0001;
    public const FLAG_COMPRESSED           = 0x0002;
    public const FLAG_PASSWORD_DERIVED     = 0x0004;
    public const FLAG_HAS_KEY_COMMITMENT   = 0x0008;
    public const FLAG_HAS_EXPIRATION       = 0x0010;
    public const FLAG_HAS_PUBLIC_METADATA  = 0x0020;
    public const FLAG_MULTI_FILE           = 0x0040;
    public const FLAG_HAS_CANARY           = 0x0080;
    public const FLAG_HAS_REDACTIONS       = 0x0100;
    public const FLAG_SPLIT_KEY            = 0x0200;
    public const FLAG_SELECTIVE_DISCLOSURE = 0x0400;
    public const FLAG_VERSIONED            = 0x0800;
    public const FLAG_REGULATORY_HOLD      = 0x1000;
    public const FLAG_HAS_TIMESTAMP        = 0x2000;
    public const FLAG_ANONYMOUS            = 0x4000;
    public const FLAG_HAS_CLASSIFICATION   = 0x8000;

    // Block type constants (uint8).
    public const BLOCK_CONTENT          = 0x01;
    public const BLOCK_METADATA         = 0x02;
    public const BLOCK_PUBLIC_METADATA  = 0x03;
    public const BLOCK_FILE_HEADER      = 0x04;
    public const BLOCK_PROVENANCE       = 0x05;
    public const BLOCK_REDACTED         = 0x06;
    public const BLOCK_ATTESTATION      = 0x07;
    public const BLOCK_REFERENCE        = 0x08;
    public const BLOCK_AUDIT            = 0x09;
    public const BLOCK_DISCLOSURE_INDEX = 0x0A;
    public const BLOCK_TIMESTAMP        = 0x0B;
    public const BLOCK_EXCERPT          = 0x0C;
    public const BLOCK_MANIFEST_ENTRY   = 0x0D;
    public const BLOCK_SIGNATURE        = 0x0E;

    // Field sizes in bytes.
    public const CONTENT_TYPE_SIZE        = 64;
    public const MAX_FILENAME_LENGTH      = 255;
    public const SALT_SIZE                = 32;
    public const HASH_SIZE                = 32;
    public const IV_SIZE                  = 12;
    public const TAG_SIZE                 = 16;
    public const SEAL_SIZE                = 64;
    public const BLOCK_DIRECTORY_ENTRY_SIZE = 65;

    // DoS limits.
    public const MAX_BLOCK_COUNT          = 1_000_000;
    public const MAX_PUBLIC_METADATA_SIZE = 10 * 1024 * 1024;
    public const MAX_FILE_SIZE            = 512 * 1024 * 1024; // safety cap for web upload

    public const HKDF_INFO_PREFIX         = 'zegel-block-key-v1:';
    public const HKDF_NONCE_PREFIX        = 'zegel-block-nonce-v1:';
}

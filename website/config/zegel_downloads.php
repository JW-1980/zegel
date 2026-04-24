<?php

/*
 * Canonical catalogue of Zegel distributions.
 *
 * Each platform lists CLI + GUI builds. Paths are relative to the public disk.
 * Installing a new build = drop the binary in storage/app/public/releases/
 * and add the filename + SHA-256 below.
 */

return [
    'version' => '1.4.0',
    'signature_algorithm' => 'HMAC-SHA512',
    'download_base' => '/releases',

    'platforms' => [
        [
            'key'   => 'windows',
            'name'  => 'Windows',
            'icon'  => 'windows',
            'notes' => 'Windows 10/11 (64-bit). Signed with Microsoft Authenticode.',
            'assets' => [
                ['kind' => 'gui', 'filename' => 'zegel-gui-1.4.0-windows-x64.exe', 'size' => 48_500_000, 'sha256' => null, 'arch' => 'x64'],
                ['kind' => 'cli', 'filename' => 'zegel-cli-1.4.0-windows-x64.zip', 'size' => 12_300_000, 'sha256' => null, 'arch' => 'x64'],
            ],
        ],
        [
            'key'   => 'macos',
            'name'  => 'macOS',
            'icon'  => 'apple',
            'notes' => 'macOS 13+. Universal build (Intel + Apple Silicon).',
            'assets' => [
                ['kind' => 'gui', 'filename' => 'zegel-gui-1.4.0-macos-universal.dmg', 'size' => 50_100_000, 'sha256' => null, 'arch' => 'universal'],
                ['kind' => 'cli', 'filename' => 'zegel-cli-1.4.0-macos-universal.tar.gz', 'size' => 11_600_000, 'sha256' => null, 'arch' => 'universal'],
            ],
        ],
        [
            'key'   => 'linux',
            'name'  => 'Linux',
            'icon'  => 'linux',
            'notes' => 'Ubuntu 22.04+, Fedora 38+, Debian 12+, and any glibc 2.35+ distro.',
            'assets' => [
                ['kind' => 'gui', 'filename' => 'zegel-gui-1.4.0-linux-x64.AppImage', 'size' => 72_000_000, 'sha256' => null, 'arch' => 'x64'],
                ['kind' => 'gui', 'filename' => 'zegel-gui-1.4.0-linux-arm64.AppImage', 'size' => 73_000_000, 'sha256' => null, 'arch' => 'arm64'],
                ['kind' => 'cli', 'filename' => 'zegel-cli-1.4.0-linux-x64.tar.gz', 'size' => 10_900_000, 'sha256' => null, 'arch' => 'x64'],
                ['kind' => 'cli', 'filename' => 'zegel-cli-1.4.0-linux-arm64.tar.gz', 'size' => 10_700_000, 'sha256' => null, 'arch' => 'arm64'],
            ],
        ],
        [
            'key'   => 'android',
            'name'  => 'Android',
            'icon'  => 'android',
            'notes' => 'Android 10+. Available via the bundled APK or Google Play.',
            'assets' => [
                ['kind' => 'gui', 'filename' => 'zegel-gui-1.4.0-android-universal.apk', 'size' => 34_000_000, 'sha256' => null, 'arch' => 'universal'],
            ],
        ],
        [
            'key'   => 'ios',
            'name'  => 'iOS',
            'icon'  => 'ios',
            'notes' => 'iOS 16+. Distributed exclusively via the App Store.',
            'assets' => [
                ['kind' => 'gui', 'filename' => 'zegel-gui-1.4.0-ios.ipa', 'size' => 26_500_000, 'sha256' => null, 'arch' => 'universal'],
            ],
        ],
    ],
];

<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Zegel\ZegelReader;
use App\Zegel\ZegelWriter;
use Illuminate\Console\Command;

/**
 * Round-trips the PHP Zegel library and verifies tamper detection and
 * wrong-key rejection. Used in CI to catch regressions.
 */
class ZegelSelftest extends Command
{
    protected $signature   = 'zegel:selftest';
    protected $description = 'Round-trips the PHP Zegel library to verify reader/writer correctness.';

    public function handle(): int
    {
        $reader = new ZegelReader();

        foreach (['Hello!', str_repeat('x', 65537 * 3 + 17)] as $i => $content) {
            $key    = random_bytes(32);
            $writer = new ZegelWriter($key);
            $sealed = $writer->seal(
                $content,
                filename: "case-$i.txt",
                contentType: 'text/plain',
                metadata: ['case' => $i],
                publicMetadata: ['issuer' => 'selftest'],
            );

            // Round-trip
            $result = $reader->verify($sealed, $key);
            $this->assert($result->content === $content, "round-trip #$i");
            $this->assert($result->metadata['case'] === $i, "metadata #$i");
            $this->assert($result->publicMetadata['issuer'] === 'selftest', "public-metadata #$i");

            // Wrong key
            try {
                $reader->verify($sealed, random_bytes(32));
                $this->error("wrong-key-not-detected #$i");
                return self::FAILURE;
            } catch (\App\Zegel\ZegelTamperedException) {
                // expected
            }

            // Tamper at arbitrary offset
            $t = $sealed;
            $off = intdiv(strlen($t), 2);
            $t[$off] = chr(ord($t[$off]) ^ 0xFF);
            try {
                $reader->verify($t, $key);
                $this->error("tamper-not-detected #$i");
                return self::FAILURE;
            } catch (\App\Zegel\ZegelTamperedException) {
                // expected
            }
        }

        $this->info('All Zegel PHP self-tests passed.');
        return self::SUCCESS;
    }

    private function assert(bool $cond, string $label): void
    {
        if (!$cond) {
            $this->error("assertion failed: $label");
            throw new \RuntimeException('self-test failed: ' . $label);
        }
    }
}

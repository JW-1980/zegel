<?php

declare(strict_types=1);

namespace Tests\Unit\Zegel;

use App\Zegel\ZegelReader;
use App\Zegel\ZegelTamperedException;
use App\Zegel\ZegelWriter;
use PHPUnit\Framework\TestCase;

class ZegelRoundTripTest extends TestCase
{
    public function test_small_content_round_trips(): void
    {
        $key = random_bytes(32);
        $writer = new ZegelWriter($key);
        $sealed = $writer->seal('Hello, Zegel!', 'hello.txt', 'text/plain',
            metadata: ['author' => 'test'],
            publicMetadata: ['issuer' => 'CI']);

        $reader = new ZegelReader();
        $result = $reader->verify($sealed, $key);

        $this->assertTrue($result->valid);
        $this->assertSame('Hello, Zegel!', $result->content);
        $this->assertSame('test', $result->metadata['author']);
        $this->assertSame('CI', $result->publicMetadata['issuer']);
        $this->assertSame('hello.txt', $result->filename);
        $this->assertSame('text/plain', $result->contentType);
    }

    public function test_multiblock_compressed_round_trips(): void
    {
        $key = random_bytes(32);
        $bytes = str_repeat("Lorem ipsum dolor sit amet. ", 3000);
        $writer = new ZegelWriter($key);
        $sealed = $writer->seal($bytes, 'large.txt', 'text/plain');

        $result = (new ZegelReader())->verify($sealed, $key);
        $this->assertTrue($result->valid);
        $this->assertSame(strlen($bytes), strlen($result->content));
    }

    public function test_wrong_key_is_rejected(): void
    {
        $key = random_bytes(32);
        $sealed = (new ZegelWriter($key))->seal('secret', 'secret.txt', 'text/plain');
        $this->expectException(ZegelTamperedException::class);
        (new ZegelReader())->verify($sealed, random_bytes(32));
    }

    public function test_tamper_is_detected_anywhere(): void
    {
        $key = random_bytes(32);
        $sealed = (new ZegelWriter($key))->seal('tamper-me', 'file.txt', 'text/plain');
        $reader = new ZegelReader();

        // Flip every 64th byte one at a time and assert detection.
        for ($i = 0; $i < strlen($sealed); $i += 64) {
            $tampered = $sealed;
            $tampered[$i] = chr(ord($tampered[$i]) ^ 0xFF);
            try {
                $reader->verify($tampered, $key);
                $this->fail('Tamper at offset ' . $i . ' was not detected');
            } catch (\App\Zegel\ZegelException) {
                // expected
            }
        }
        $this->addToAssertionCount(1);
    }
}

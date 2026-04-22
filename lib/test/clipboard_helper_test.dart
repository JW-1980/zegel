import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ClipboardHelper', () {
    group('hash', () {
      test('returns a ClipboardItem with the supplied hex value', () {
        const hex = 'deadbeef01234567';
        final item = ClipboardHelper.hash(hex);
        expect(item.value, hex);
      });

      test('is not sensitive', () {
        final item = ClipboardHelper.hash('aabbccdd');
        expect(item.sensitive, isFalse);
      });

      test('autoClear is null (hash values are not auto-cleared)', () {
        final item = ClipboardHelper.hash('aabbccdd');
        expect(item.autoClear, isNull);
      });

      test('default label is "Hash"', () {
        final item = ClipboardHelper.hash('ff00');
        expect(item.label, 'Hash');
      });

      test('accepts a custom label', () {
        final item = ClipboardHelper.hash('ff00', label: 'Merkle root');
        expect(item.label, 'Merkle root');
      });
    });

    group('secret', () {
      test('returns a ClipboardItem with the supplied value', () {
        const secret = 's3cr3t-k3y!';
        final item = ClipboardHelper.secret(secret);
        expect(item.value, secret);
      });

      test('is marked sensitive', () {
        final item = ClipboardHelper.secret('key');
        expect(item.sensitive, isTrue);
      });

      test('default autoClear equals defaultAutoClear (45 s)', () {
        final item = ClipboardHelper.secret('key');
        expect(item.autoClear, ClipboardHelper.defaultAutoClear);
        expect(item.autoClear, const Duration(seconds: 45));
      });

      test('accepts a custom autoClear duration', () {
        final custom = const Duration(seconds: 10);
        final item = ClipboardHelper.secret('key', autoClear: custom);
        expect(item.autoClear, custom);
      });

      test('default label is "Secret"', () {
        final item = ClipboardHelper.secret('hidden');
        expect(item.label, 'Secret');
      });

      test('accepts a custom label', () {
        final item = ClipboardHelper.secret('key', label: 'Master key');
        expect(item.label, 'Master key');
      });
    });

    group('previewFor — non-sensitive items', () {
      test('returns full value when at or below 40 chars', () {
        final item = ClipboardHelper.hash('a' * 40);
        expect(ClipboardHelper.previewFor(item), 'a' * 40);
      });

      test('returns full value for short hashes', () {
        final item = ClipboardHelper.hash('deadbeef');
        expect(ClipboardHelper.previewFor(item), 'deadbeef');
      });

      test('truncates value longer than 40 chars with ellipsis', () {
        final item = ClipboardHelper.hash('a' * 50);
        final preview = ClipboardHelper.previewFor(item);
        expect(preview.endsWith('…'), isTrue);
        // Should be 37 chars + '…' = 38 chars total.
        expect(preview.length, 38);
      });

      test('truncated prefix is exactly 37 characters', () {
        final value = 'x' * 50;
        final item = ClipboardHelper.hash(value);
        final preview = ClipboardHelper.previewFor(item);
        expect(preview, startsWith('x' * 37));
      });

      test('value of exactly 41 chars is truncated', () {
        final item = ClipboardHelper.hash('b' * 41);
        final preview = ClipboardHelper.previewFor(item);
        expect(preview.endsWith('…'), isTrue);
      });
    });

    group('previewFor — sensitive items', () {
      test('very short value is fully masked', () {
        final item = ClipboardHelper.secret('ab');
        final preview = ClipboardHelper.previewFor(item);
        expect(preview, '••');
        expect(preview.length, 2);
      });

      test('value of exactly 4 chars is fully masked', () {
        final item = ClipboardHelper.secret('abcd');
        final preview = ClipboardHelper.previewFor(item);
        expect(preview, '••••');
      });

      test('value longer than 4 chars shows 2-char prefix then ellipsis then dots', () {
        final item = ClipboardHelper.secret('supersecret');
        final preview = ClipboardHelper.previewFor(item);
        // Pattern: first 2 chars + '…' + '••••'
        expect(preview, startsWith('su'));
        expect(preview, contains('…'));
        expect(preview, endsWith('••••'));
      });

      test('sensitive preview for value of 5 chars follows masking pattern', () {
        final item = ClipboardHelper.secret('hello');
        final preview = ClipboardHelper.previewFor(item);
        expect(preview, 'he…••••');
      });

      test('sensitive preview never exposes more than 2 plaintext chars', () {
        final item = ClipboardHelper.secret('my-very-long-master-key-hex-data');
        final preview = ClipboardHelper.previewFor(item);
        // Preview should show 'my' then mask the rest.
        expect(preview, startsWith('my'));
        // The rest should not contain any plaintext from the value.
        final tail = preview.substring(2);
        expect(tail, isNot(contains('v')));
      });

      test('single character value is fully masked', () {
        final item = ClipboardHelper.secret('x');
        expect(ClipboardHelper.previewFor(item), '•');
      });
    });

    group('ClipboardItem properties', () {
      test('hash item constructed correctly via ClipboardItem directly', () {
        const item = ClipboardItem(
          value: 'test',
          label: 'Test',
          autoClear: null,
          sensitive: false,
        );
        expect(item.value, 'test');
        expect(item.label, 'Test');
        expect(item.autoClear, isNull);
        expect(item.sensitive, isFalse);
      });

      test('sensitive item constructed correctly via ClipboardItem directly', () {
        const item = ClipboardItem(
          value: 'secret',
          label: 'Key',
          autoClear: Duration(seconds: 30),
          sensitive: true,
        );
        expect(item.sensitive, isTrue);
        expect(item.autoClear, const Duration(seconds: 30));
      });
    });

    group('defaultAutoClear constant', () {
      test('is 45 seconds', () {
        expect(ClipboardHelper.defaultAutoClear, const Duration(seconds: 45));
      });
    });
  });
}

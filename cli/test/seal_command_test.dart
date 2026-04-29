import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('SealCommand Error Tests', () {
    late File inputTemp;
    late File outputTemp;

    setUp(() {
      inputTemp = File('test_input_seal_error.txt')..writeAsStringSync('test data');
      outputTemp = File('test_output_seal_error.zgl');
    });

    tearDown(() {
      if (inputTemp.existsSync()) inputTemp.deleteSync();
      if (outputTemp.existsSync()) outputTemp.deleteSync();
    });

    test('invalid format in expiration date', () async {
      final key = '00' * 32;

      final result = await Process.run('dart', [
        'bin/zegel.dart',
        'seal',
        inputTemp.path,
        '-k',
        key,
        '-o',
        outputTemp.path,
        '--expires',
        'invalid-date',
      ]);

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Invalid expiration date format'));
    });

    test('invalid format in classification level', () async {
      final key = '00' * 32;

      final result = await Process.run('dart', [
        'bin/zegel.dart',
        'seal',
        inputTemp.path,
        '-k',
        key,
        '-o',
        outputTemp.path,
        '--classification',
        'INVALID_LEVEL',
      ]);

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Invalid classification level: "INVALID_LEVEL"'));
    });

    test('invalid format in recipient-id (non-hex)', () async {
      final key = '00' * 32;

      final result = await Process.run('dart', [
        'bin/zegel.dart',
        'seal',
        inputTemp.path,
        '-k',
        key,
        '-o',
        outputTemp.path,
        '--recipient-id',
        'ZZ' * 32,
      ]);

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Invalid hex recipient-id: contains non-hex characters.'));
    });

    test('invalid format in recipient-id (wrong length)', () async {
      final key = '00' * 32;

      final result = await Process.run('dart', [
        'bin/zegel.dart',
        'seal',
        inputTemp.path,
        '-k',
        key,
        '-o',
        outputTemp.path,
        '--recipient-id',
        '00' * 31,
      ]);

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Recipient ID must be exactly 32 bytes (64 hex characters). Got 31 bytes.'));
    });
  });
}

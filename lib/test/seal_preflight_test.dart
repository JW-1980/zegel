import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('SealPreflight', () {
    test('empty file produces an error warning', () {
      final result = SealPreflight.analyse(Uint8List(0));
      expect(
        result.warnings.any((w) => w.code == 'empty_file'),
        isTrue,
      );
      expect(result.safeToProceed, isFalse);
    });

    test('oversize file emits an info warning', () {
      final bytes = Uint8List(512);
      final result = SealPreflight.analyse(bytes, oversizeThreshold: 100);
      expect(
        result.warnings.any((w) => w.code == 'oversize_file'),
        isTrue,
      );
    });

    test('PII-bearing text triggers a warning', () {
      final bytes = Uint8List.fromList(
        utf8.encode('Email me at alice@example.com'),
      );
      final result = SealPreflight.analyse(bytes);
      expect(
        result.warnings.any((w) => w.code == 'pii_detected'),
        isTrue,
      );
      expect(result.hasWarnings, isTrue);
    });

    test('weak password triggers a warning', () {
      final bytes = Uint8List.fromList(utf8.encode('safe content'));
      final result = SealPreflight.analyse(bytes, password: '123');
      expect(
        result.warnings.any((w) => w.code == 'weak_password'),
        isTrue,
      );
    });

    test('strong password and clean text produce no warnings', () {
      final bytes = Uint8List.fromList(utf8.encode('routine corporate text'));
      final result = SealPreflight.analyse(
        bytes,
        password: 'Xh%9q2Rn4!bT2#vE7gJk',
      );
      expect(result.hasErrors, isFalse);
      expect(
        result.warnings.any((w) => w.code == 'weak_password'),
        isFalse,
      );
    });
  });
}

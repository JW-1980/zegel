import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('FeedbackSubmitter', () {
    late Directory tempDir;
    late String storagePath;
    late FeedbackSubmitter submitter;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zegel_feedback_test_');
      storagePath = '${tempDir.path}/feedback.ndjson';
      submitter = FeedbackSubmitter(storagePath: storagePath);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    group('submit', () {
      test('returns a FeedbackEntry with the supplied fields', () {
        final entry = submitter.submit(
          category: FeedbackCategory.bug,
          message: 'Something broke',
          email: 'user@example.com',
          screen: 'SealScreen',
        );
        expect(entry.category, FeedbackCategory.bug);
        expect(entry.message, 'Something broke');
        expect(entry.email, 'user@example.com');
        expect(entry.screen, 'SealScreen');
      });

      test('assigns a non-empty id to the entry', () {
        final entry = submitter.submit(
          category: FeedbackCategory.feature,
          message: 'Please add X',
        );
        expect(entry.id, isNotEmpty);
        expect(entry.id, startsWith('fb_'));
      });

      test('at defaults to a UTC time close to now', () {
        final before = DateTime.now().toUtc().subtract(
          const Duration(seconds: 1),
        );
        final entry = submitter.submit(
          category: FeedbackCategory.other,
          message: 'Hello',
        );
        final after = DateTime.now().toUtc().add(const Duration(seconds: 1));
        expect(entry.at.isAfter(before), isTrue);
        expect(entry.at.isBefore(after), isTrue);
        expect(entry.at.isUtc, isTrue);
      });

      test('accepts an explicit at timestamp', () {
        final fixed = DateTime.utc(2025, 6, 15, 12, 0, 0);
        final entry = submitter.submit(
          category: FeedbackCategory.praise,
          message: 'Great work',
          at: fixed,
        );
        expect(entry.at, fixed);
      });

      test('writes JSON line to the storage file', () {
        submitter.submit(category: FeedbackCategory.question, message: 'Why?');
        final file = File(storagePath);
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync().trim();
        expect(content, isNotEmpty);
        expect(content, contains('"category":"question"'));
        expect(content, contains('"message":"Why?"'));
      });

      test('multiple submits append distinct lines', () {
        submitter.submit(category: FeedbackCategory.bug, message: 'Bug 1');
        submitter.submit(category: FeedbackCategory.bug, message: 'Bug 2');
        submitter.submit(
          category: FeedbackCategory.feature,
          message: 'Feature 1',
        );
        final lines = File(storagePath)
            .readAsStringSync()
            .trim()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        expect(lines.length, 3);
      });

      test('creates parent directories when they do not exist', () {
        final deep = '${tempDir.path}/a/b/c/feedback.ndjson';
        final s = FeedbackSubmitter(storagePath: deep);
        s.submit(category: FeedbackCategory.other, message: 'test');
        expect(File(deep).existsSync(), isTrue);
      });

      test('optional email is omitted from JSON when not provided', () {
        submitter.submit(category: FeedbackCategory.bug, message: 'No email');
        final content = File(storagePath).readAsStringSync();
        expect(content, isNot(contains('"email"')));
      });

      test('optional screen is omitted from JSON when not provided', () {
        submitter.submit(category: FeedbackCategory.bug, message: 'No screen');
        final content = File(storagePath).readAsStringSync();
        expect(content, isNot(contains('"screen"')));
      });

      test('context is stored and serialised', () {
        submitter.submit(
          category: FeedbackCategory.bug,
          message: 'With context',
          context: <String, dynamic>{'version': '1.2.0', 'platform': 'linux'},
        );
        final content = File(storagePath).readAsStringSync();
        expect(content, contains('version'));
        expect(content, contains('1.2.0'));
      });
    });

    group('list', () {
      test('returns empty list when no entries have been submitted', () {
        expect(submitter.list(), isEmpty);
      });

      test('returns empty list when file does not exist', () {
        final s = FeedbackSubmitter(
          storagePath: '/tmp/nonexistent_zgl_feedback.ndjson',
        );
        expect(s.list(), isEmpty);
      });

      test('returns every submitted entry in order', () {
        submitter.submit(category: FeedbackCategory.bug, message: 'First');
        submitter.submit(category: FeedbackCategory.feature, message: 'Second');
        submitter.submit(category: FeedbackCategory.question, message: 'Third');
        final entries = submitter.list();
        expect(entries.length, 3);
        expect(entries[0].message, 'First');
        expect(entries[1].message, 'Second');
        expect(entries[2].message, 'Third');
      });

      test('correctly deserialises category', () {
        submitter.submit(category: FeedbackCategory.praise, message: 'Yay');
        expect(submitter.list().first.category, FeedbackCategory.praise);
      });

      test('correctly deserialises email and screen when present', () {
        submitter.submit(
          category: FeedbackCategory.bug,
          message: 'Crash',
          email: 'a@b.com',
          screen: 'HomeScreen',
        );
        final entry = submitter.list().first;
        expect(entry.email, 'a@b.com');
        expect(entry.screen, 'HomeScreen');
      });

      test('email and screen are null when absent', () {
        submitter.submit(category: FeedbackCategory.other, message: 'Bare');
        final entry = submitter.list().first;
        expect(entry.email, isNull);
        expect(entry.screen, isNull);
      });

      test('at timestamp survives round trip as UTC', () {
        final fixed = DateTime.utc(2026, 1, 10, 9, 30, 0);
        submitter.submit(
          category: FeedbackCategory.bug,
          message: 'Time test',
          at: fixed,
        );
        final entry = submitter.list().first;
        expect(entry.at, fixed);
        expect(entry.at.isUtc, isTrue);
      });

      test('context map survives round trip', () {
        submitter.submit(
          category: FeedbackCategory.bug,
          message: 'ctx',
          context: <String, dynamic>{'key': 'value', 'count': 3},
        );
        final entry = submitter.list().first;
        expect(entry.context['key'], 'value');
        expect(entry.context['count'], 3);
      });

      test('all FeedbackCategory values can be submitted and read back', () {
        for (final cat in FeedbackCategory.values) {
          final s = FeedbackSubmitter(
            storagePath: '${tempDir.path}/cat_${cat.name}.ndjson',
          );
          s.submit(category: cat, message: 'test');
          expect(s.list().first.category, cat);
        }
      });
    });

    group('clear', () {
      test('removes the storage file', () {
        submitter.submit(category: FeedbackCategory.bug, message: 'data');
        submitter.clear();
        expect(File(storagePath).existsSync(), isFalse);
      });

      test('after clear, list returns empty', () {
        submitter.submit(category: FeedbackCategory.bug, message: 'data');
        submitter.clear();
        expect(submitter.list(), isEmpty);
      });

      test('clear when file does not exist is a no-op', () {
        expect(() => submitter.clear(), returnsNormally);
      });

      test('submit after clear creates a fresh file', () {
        submitter.submit(
          category: FeedbackCategory.bug,
          message: 'Before clear',
        );
        submitter.clear();
        submitter.submit(
          category: FeedbackCategory.feature,
          message: 'After clear',
        );
        final entries = submitter.list();
        expect(entries.length, 1);
        expect(entries.first.message, 'After clear');
      });
    });

    group('FeedbackEntry.toJson / fromJson round trip', () {
      test('survives toJson/fromJson with all fields', () {
        final original = submitter.submit(
          category: FeedbackCategory.bug,
          message: 'Round trip',
          email: 'rt@example.com',
          screen: 'Screen',
          context: <String, dynamic>{'k': 'v'},
          at: DateTime.utc(2026, 3, 1, 8, 0),
        );
        final restored = FeedbackEntry.fromJson(original.toJson());
        expect(restored.id, original.id);
        expect(restored.at, original.at);
        expect(restored.category, original.category);
        expect(restored.message, original.message);
        expect(restored.email, original.email);
        expect(restored.screen, original.screen);
        expect(restored.context, original.context);
      });

      test('unknown category in JSON falls back to other', () {
        final json = <String, dynamic>{
          'id': 'fb_test',
          'at': DateTime.utc(2026, 1, 1).toIso8601String(),
          'category': 'totally_unknown_category',
          'message': 'test',
          'context': <String, dynamic>{},
        };
        final entry = FeedbackEntry.fromJson(json);
        expect(entry.category, FeedbackCategory.other);
      });
    });
  });
}

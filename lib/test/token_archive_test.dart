import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('TokenArchive', () {
    late Directory tmp;
    late TokenArchive archive;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('zegel_token_test_');
      archive = TokenArchive(
        liveDirectory: '${tmp.path}/live',
        archiveDirectory: '${tmp.path}/archive',
      );
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('addToken places file in live directory', () {
      archive.addToken(
        'tok-1',
        jsonEncode({'signer': 'alice'}),
        expiresAt: DateTime.utc(2030, 1, 1),
      );
      expect(archive.liveTokens(), ['tok-1']);
      expect(archive.archivedTokens(), isEmpty);
    });

    test('sweep moves expired tokens (meta-based) to archive', () {
      archive.addToken(
        'old',
        jsonEncode({'signer': 'alice'}),
        expiresAt: DateTime.utc(2000, 1, 1),
      );
      archive.addToken(
        'future',
        jsonEncode({'signer': 'bob'}),
        expiresAt: DateTime.utc(2099, 1, 1),
      );

      final archived = archive.sweep(now: DateTime.utc(2026, 6, 1));
      expect(archived, ['old']);
      expect(archive.liveTokens(), ['future']);
      expect(archive.archivedTokens(), ['old']);
    });

    test('sweep falls back to inline expires_at when meta is absent', () {
      archive.addToken(
        'inline',
        jsonEncode({'expires_at': '2000-01-01T00:00:00Z'}),
      );

      final archived = archive.sweep(now: DateTime.utc(2026, 6, 1));
      expect(archived, ['inline']);
    });

    test('tokens without expiration remain live', () {
      archive.addToken('immortal', jsonEncode({'data': 'anything'}));
      final archived = archive.sweep(now: DateTime.utc(9999, 1, 1));
      expect(archived, isEmpty);
      expect(archive.liveTokens(), ['immortal']);
    });
  });
}

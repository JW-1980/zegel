import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('RevealInOs', () {
    group('commandFor – windows', () {
      test('uses explorer executable', () {
        final cmd = RevealInOs.commandFor(
          r'C:\Users\alice\secret.zgl',
          overrideOs: 'windows',
        );
        expect(cmd.executable, 'explorer');
      });

      test('passes /select,"<path>" as single argument', () {
        const path = r'C:\Users\alice\secret.zgl';
        final expectedPath = File(path).absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments, ['/select,"$expectedPath"']);
      });

      test('works for paths with spaces', () {
        const path = r'C:\My Documents\report.zgl';
        final expectedPath = File(path).absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments.first, '/select,"$expectedPath"');
      });
    });

    group('commandFor – macos', () {
      test('uses open executable', () {
        final cmd = RevealInOs.commandFor(
          '/Users/alice/Documents/secret.zgl',
          overrideOs: 'macos',
        );
        expect(cmd.executable, 'open');
      });

      test('passes -R and -- flags followed by the path', () {
        const path = '/Users/alice/Documents/secret.zgl';
        final expectedPath = File(path).absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'macos');
        expect(cmd.arguments, ['-R', '--', expectedPath]);
      });

      test('arguments list has exactly three elements', () {
        final cmd = RevealInOs.commandFor(
          '/tmp/foo.zgl',
          overrideOs: 'macos',
        );
        expect(cmd.arguments.length, 3);
      });
    });

    group('commandFor – linux', () {
      test('uses xdg-open executable', () {
        final cmd = RevealInOs.commandFor(
          '/home/alice/docs/secret.zgl',
          overrideOs: 'linux',
        );
        expect(cmd.executable, 'xdg-open');
      });

      test('passes -- and the parent directory, not the file itself', () {
        const path = '/home/alice/docs/secret.zgl';
        final expectedPath = File(path).absolute.path;
        final expectedParent = expectedPath.substring(
            0, expectedPath.lastIndexOf(Platform.pathSeparator));
        final cmd = RevealInOs.commandFor(
          path,
          overrideOs: 'linux',
        );
        expect(cmd.arguments, ['--', expectedParent]);
      });

      test('handles file in root directory gracefully', () {
        const path = '/secret.zgl';
        final expectedPath = File(path).absolute.path;
        final idx = expectedPath.lastIndexOf(Platform.pathSeparator);
        final expectedParent =
            idx <= 0 ? expectedPath : expectedPath.substring(0, idx);
        final cmd = RevealInOs.commandFor(
          path,
          overrideOs: 'linux',
        );
        // The file is at the root; the parent resolution falls back to
        // the path itself when idx <= 0.
        expect(cmd.arguments.length, 2);
        expect(cmd.arguments[0], '--');
        expect(cmd.arguments[1], expectedParent);
      });

      test('arguments list has exactly two elements', () {
        final cmd = RevealInOs.commandFor(
          '/var/data/report.zgl',
          overrideOs: 'linux',
        );
        expect(cmd.arguments.length, 2);
      });
    });

    group('commandFor – security', () {
      test('rejects URIs', () {
        expect(
          () => RevealInOs.commandFor('file:///tmp/secret.zgl'),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => RevealInOs.commandFor('http://example.com/secret.zgl'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('commandFor – unsupported OS', () {
      test('throws UnsupportedError for unknown platform', () {
        expect(
          () => RevealInOs.commandFor('/tmp/file.zgl', overrideOs: 'fuchsia'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('throws UnsupportedError for empty string platform', () {
        expect(
          () => RevealInOs.commandFor('/tmp/file.zgl', overrideOs: ''),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('error message mentions the unsupported OS name', () {
        try {
          RevealInOs.commandFor('/tmp/file.zgl', overrideOs: 'android');
          fail('expected UnsupportedError');
        } on UnsupportedError catch (e) {
          expect(e.message, contains('android'));
        }
      });
    });

    group('RevealCommand', () {
      test('stores executable and arguments', () {
        const cmd = RevealCommand(
          executable: 'myexe',
          arguments: ['--flag', 'val'],
        );
        expect(cmd.executable, 'myexe');
        expect(cmd.arguments, ['--flag', 'val']);
      });
    });
  });
}

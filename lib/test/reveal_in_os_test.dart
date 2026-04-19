import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('RevealInOs', () {
    test('throws ArgumentError for paths containing URI schemes', () {
      expect(
        () => RevealInOs.commandFor('http://example.com/file.zgl'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RevealInOs.commandFor('file:///path/to/file.zgl'),
        throwsA(isA<ArgumentError>()),
      );
    });

    group('commandFor – windows', () {
      test('uses explorer executable', () {
        final cmd = RevealInOs.commandFor(
          r'C:\Users\alice\secret.zgl',
          overrideOs: 'windows',
        );
        expect(cmd.executable, 'explorer');
      });

      test('passes /select,"<absolutePath>" as single argument', () {
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

      test('passes -R flag, -- separator, followed by the absolute path', () {
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

      test('passes -- separator and the parent directory, not the file itself',
          () {
        final path = '/home/alice/docs/secret.zgl';
        final expectedPath = File(path).absolute.path;
        final sep = Platform.pathSeparator;
        final idx = expectedPath.lastIndexOf(sep);
        final expectedParent =
            idx <= 0 ? expectedPath : expectedPath.substring(0, idx);
        final cmd = RevealInOs.commandFor(path, overrideOs: 'linux');
        expect(cmd.arguments, ['--', expectedParent]);
      });

      test('handles file in root directory gracefully', () {
        final cmd = RevealInOs.commandFor(
          '/secret.zgl',
          overrideOs: 'linux',
        );
        // The file is at the root; the parent resolution falls back to
        // the path itself when idx <= 0.
        expect(cmd.arguments.length, 2);
        expect(cmd.arguments.first, '--');
        expect(cmd.arguments.last, isNotEmpty);
      });

      test('arguments list has exactly two elements', () {
        final cmd = RevealInOs.commandFor(
          '/var/data/report.zgl',
          overrideOs: 'linux',
        );
        expect(cmd.arguments.length, 2);
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

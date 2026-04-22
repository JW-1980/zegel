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
        final path = File(r'C:\Users\alice\secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments, ['/select,"$path"']);
      });

      test('works for paths with spaces', () {
        final path = File(r'C:\My Documents\report.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments.first, '/select,"$path"');
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

      test('passes -R flag followed by -- separator and the path', () {
        final path = File('/Users/alice/Documents/secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'macos');
        expect(cmd.arguments, ['-R', '--', path]);
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

      test('passes the parent directory, not the file itself, prefixed by --',
          () {
        final file = File('/home/alice/docs/secret.zgl').absolute;
        final parentDir = file.parent.path;
        final cmd = RevealInOs.commandFor(
          file.path,
          overrideOs: 'linux',
        );
        expect(cmd.arguments, ['--', parentDir]);
      });

      test('handles file in root directory gracefully', () {
        final file = File('/secret.zgl').absolute;

        // _parentOf has a fallback `if (idx <= 0) return path;`
        // In Dart, File('/secret.zgl').absolute.path is typically /secret.zgl.
        // lastIndexOf('/') == 0. Thus `idx <= 0` is true and it returns the original path.
        final cmd = RevealInOs.commandFor(
          file.path,
          overrideOs: 'linux',
        );
        // The file is at the root; the parent resolution falls back to
        // the path itself when idx <= 0.
        expect(cmd.arguments.length, 2);
        expect(cmd.arguments[1], file.path);
      });

      test('arguments list has exactly two elements', () {
        final cmd = RevealInOs.commandFor(
          '/var/data/report.zgl',
          overrideOs: 'linux',
        );
        expect(cmd.arguments.length, 2);
      });
    });

    group('commandFor – URI rejection', () {
      test('rejects file:// URIs', () {
        expect(
          () => RevealInOs.commandFor('file:///tmp/secret.zgl'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('URI schemes are not supported'),
          )),
        );
      });

      test('rejects http:// URIs', () {
        expect(
          () => RevealInOs.commandFor('http://example.com/secret.zgl'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('URI schemes are not supported'),
          )),
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

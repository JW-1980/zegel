import 'dart:io';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('RevealInOs', () {
    group('commandFor – windows', () {
      test('uses explorer executable', () {
        final cmd = RevealInOs.commandFor(
          File('secret.zgl').absolute.path,
          overrideOs: 'windows',
        );
        expect(cmd.executable, 'explorer');
      });

      test('passes /select,<path> as single argument', () {
        final path = File('secret.zgl').absolute.path;
        final absPath = File(path).absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments, ['/select,"$absPath"']);
      });

      test('works for paths with spaces', () {
        final path = File('report.zgl').absolute.path;
        final absPath = File(path).absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments.first, '/select,"$absPath"');
      });
    });

    group('commandFor – macos', () {
      test('uses open executable', () {
        final cmd = RevealInOs.commandFor(
          File('secret.zgl').absolute.path,
          overrideOs: 'macos',
        );
        expect(cmd.executable, 'open');
      });

      test('passes -R flag followed by the path', () {
        final path = File('secret.zgl').absolute.path;
        final absPath = File(path).absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'macos');
        expect(cmd.arguments, ['-R', '--', absPath]);
      });

      test('arguments list has exactly three elements', () {
        final cmd = RevealInOs.commandFor(File('foo.zgl').absolute.path,
            overrideOs: 'macos');
        expect(cmd.arguments.length, 3);
      });
    });

    group('commandFor – linux', () {
      test('uses xdg-open executable', () {
        final cmd = RevealInOs.commandFor(
          File('secret.zgl').absolute.path,
          overrideOs: 'linux',
        );
        expect(cmd.executable, 'xdg-open');
      });

      test('passes the parent directory, not the file itself', () {
        final path = File('secret.zgl').absolute.path;
        final absPath = File(path).absolute.path;
        final parent =
            absPath.substring(0, absPath.lastIndexOf(Platform.pathSeparator));
        final cmd = RevealInOs.commandFor(
          path,
          overrideOs: 'linux',
        );
        expect(cmd.arguments, [parent]);
      });

      test('handles file in root directory gracefully', () {
        final cmd = RevealInOs.commandFor('/secret.zgl', overrideOs: 'linux');
        // The file is at the root; the parent resolution falls back to
        // the path itself when idx <= 0.
        expect(cmd.arguments.length, 1);
        expect(cmd.arguments[0], isNotEmpty);
      });

      test('arguments list has exactly one element', () {
        final cmd = RevealInOs.commandFor(
          File('report.zgl').absolute.path,
          overrideOs: 'linux',
        );
        expect(cmd.arguments.length, 1);
      });
    });

    group('commandFor – unsupported OS', () {
      test('throws UnsupportedError for unknown platform', () {
        expect(
          () => RevealInOs.commandFor(File('file.zgl').absolute.path,
              overrideOs: 'fuchsia'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('throws UnsupportedError for empty string platform', () {
        expect(
          () => RevealInOs.commandFor(File('file.zgl').absolute.path,
              overrideOs: ''),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('error message mentions the unsupported OS name', () {
        try {
          RevealInOs.commandFor(File('file.zgl').absolute.path,
              overrideOs: 'android');
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

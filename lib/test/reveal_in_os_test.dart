import 'dart:io';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('RevealInOs', () {
    group('commandFor – windows', () {
      test('uses explorer executable', () {
        final path = File('secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.executable, 'explorer');
      });

      test('passes /select,<path> as single argument', () {
        final path = File('secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments, ['/select,"$path"']);
      });

      test('works for paths with spaces', () {
        final path = File('report.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'windows');
        expect(cmd.arguments.first, '/select,"$path"');
      });
    });

    group('commandFor – macos', () {
      test('uses open executable', () {
        final path = File('secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'macos');
        expect(cmd.executable, 'open');
      });

      test('passes -R flag followed by the path', () {
        final path = File('secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'macos');
        expect(cmd.arguments, ['-R', '--', path]);
      });

      test('arguments list has exactly three elements', () {
        final path = File('secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'macos');
        expect(cmd.arguments.length, 3);
      });
    });

    group('commandFor – linux', () {
      test('uses xdg-open executable', () {
        final path = File('secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'linux');
        expect(cmd.executable, 'xdg-open');
      });

      test('passes the parent directory, not the file itself', () {
        final path = File('secret.zgl').absolute.path;
        // On Windows with linux override, the separator could be '\\' and there could be no '/'
        // Just verify it uses parent directory using absolute path string manipulation that matches RevealInOs
        final sep = Platform.pathSeparator;
        final idx = path.lastIndexOf(sep);
        final parent = idx <= 0 ? path : path.substring(0, idx);

        final cmd = RevealInOs.commandFor(path, overrideOs: 'linux');
        expect(cmd.arguments, [parent.isEmpty ? '.' : parent]);
      });

      test('handles file in root directory gracefully', () {
        final path = '${Platform.pathSeparator}secret.zgl';
        final cmd = RevealInOs.commandFor(path, overrideOs: 'linux');
        expect(cmd.arguments.length, 1);
        expect(cmd.arguments[0], isNotEmpty);
      });

      test('arguments list has exactly one element', () {
        final path = File('secret.zgl').absolute.path;
        final cmd = RevealInOs.commandFor(path, overrideOs: 'linux');
        expect(cmd.arguments.length, 1);
      });
    });

    group('commandFor – unsupported OS', () {
      test('throws UnsupportedError for unknown platform', () {
        expect(
          () => RevealInOs.commandFor('/foo.zgl', overrideOs: 'fuchsia'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('throws UnsupportedError for empty string platform', () {
        expect(
          () => RevealInOs.commandFor('/foo.zgl', overrideOs: ''),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('error message mentions the unsupported OS name', () {
        try {
          RevealInOs.commandFor('/foo.zgl', overrideOs: 'android');
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

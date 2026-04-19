import 'dart:io';

/// Reveal-in-OS command helper (improvement #45).
///
/// Translates a file path into the native command that opens the
/// containing folder with the file highlighted. The command is returned
/// rather than executed so callers can review it and keep the library
/// free from process-spawning side effects.
///
/// - Windows: `explorer /select,<path>`
/// - macOS:   `open -R <path>`
/// - Linux:   `xdg-open <parent-dir>`
///   (Most Linux file managers don't support "highlight this file", so
///   we open the parent directory instead.)
class RevealInOs {
  RevealInOs._();

  /// Returns the command [executable] and [arguments] needed to reveal
  /// [path] on the current platform. Callers typically run this as
  /// `Process.run(command.executable, command.arguments)`.
  static RevealCommand commandFor(
    String path, {
    String? overrideOs,
  }) {
    if (path.contains('://')) {
      throw ArgumentError('URI schemes are not allowed');
    }

    final absolutePath = File(path).absolute.path;

    final os = overrideOs ?? Platform.operatingSystem;
    switch (os) {
      case 'windows':
        return RevealCommand(
          executable: 'explorer',
          arguments: <String>['/select,"$absolutePath"'],
        );
      case 'macos':
        return RevealCommand(
          executable: 'open',
          arguments: <String>['-R', '--', absolutePath],
        );
      case 'linux':
        return RevealCommand(
          executable: 'xdg-open',
          arguments: <String>['--', _parentOf(absolutePath)],
        );
      default:
        throw UnsupportedError('Reveal-in-OS is not supported on $os');
    }
  }

  /// Convenience wrapper that actually runs the command. Returns the
  /// process exit code.
  static Future<int> reveal(String path) async {
    final command = commandFor(path);
    final result = await Process.run(command.executable, command.arguments);
    return result.exitCode;
  }

  static String _parentOf(String path) {
    final sep = Platform.pathSeparator;
    final idx = path.lastIndexOf(sep);
    if (idx <= 0) return path;
    return path.substring(0, idx);
  }
}

class RevealCommand {
  const RevealCommand({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;
}

/// CLI cron-job template generation (improvement #27).
///
/// Generates crontab entries and systemd timer units for routine Zegel
/// tasks (batch verification, key backup, token sweeps). The goal is to
/// spare users from hand-editing cron syntax — they pick a preset and
/// receive a copy-pasteable line or unit file.
class CronTemplate {
  CronTemplate._();

  /// Common preset schedules, mapped to the standard 5-field cron expression.
  static const Map<String, String> presets = {
    'every_minute': '* * * * *',
    'every_five_minutes': '*/5 * * * *',
    'hourly': '0 * * * *',
    'daily_midnight': '0 0 * * *',
    'daily_three_am': '0 3 * * *',
    'weekly_sunday': '0 0 * * 0',
    'monthly_first': '0 0 1 * *',
    'yearly': '0 0 1 1 *',
  };

  /// Returns the cron expression for [preset], or throws [ArgumentError] if
  /// the preset is unknown.
  static String preset(String preset) {
    final value = presets[preset];
    if (value == null) {
      throw ArgumentError('Unknown cron preset: $preset');
    }
    return value;
  }

  /// Builds a crontab line for the given [command].
  ///
  /// [schedule] may be either a preset key from [presets] or a literal cron
  /// expression. Optional [description] becomes a `# comment` on the line
  /// above, and [environment] is rendered as `KEY=value` pairs on the
  /// preceding lines (POSIX cron syntax).
  static String crontabLine({
    required String schedule,
    required String command,
    String? description,
    Map<String, String>? environment,
  }) {
    final expr = presets[schedule] ?? schedule;
    _validateCronExpression(expr);
    final sb = StringBuffer();
    if (description != null && description.isNotEmpty) {
      sb.writeln('# ${description.replaceAll('\n', ' ')}');
    }
    if (environment != null) {
      for (final entry in environment.entries) {
        sb.writeln('${entry.key}=${entry.value}');
      }
    }
    sb.write('$expr $command');
    return sb.toString();
  }

  /// Builds a minimal systemd timer + service unit pair. Returns a record
  /// with the two unit file bodies: `service` and `timer`.
  static ({String service, String timer}) systemdUnits({
    required String unitName,
    required String description,
    required String execStart,
    required String onCalendar,
    String? workingDirectory,
  }) {
    if (unitName.isEmpty || unitName.contains(' ')) {
      throw ArgumentError('unitName must be non-empty and contain no spaces');
    }
    final service = StringBuffer()
      ..writeln('[Unit]')
      ..writeln('Description=$description')
      ..writeln()
      ..writeln('[Service]')
      ..writeln('Type=oneshot')
      ..writeln('ExecStart=$execStart');
    if (workingDirectory != null) {
      service.writeln('WorkingDirectory=$workingDirectory');
    }

    final timer = StringBuffer()
      ..writeln('[Unit]')
      ..writeln('Description=$description (timer)')
      ..writeln()
      ..writeln('[Timer]')
      ..writeln('OnCalendar=$onCalendar')
      ..writeln('Persistent=true')
      ..writeln('Unit=$unitName.service')
      ..writeln()
      ..writeln('[Install]')
      ..writeln('WantedBy=timers.target');

    return (service: service.toString(), timer: timer.toString());
  }

  /// Convenience builder for the most common Zegel routines.
  ///
  /// Produces a crontab line for one of:
  /// - `batch_verify`: verifies all .zgl files in a folder.
  /// - `key_backup`:   backs up a key file to a target directory.
  /// - `token_sweep`:  archives expired selective-disclosure tokens.
  static String zegelRoutine({
    required String routine,
    required String schedule,
    required String binaryPath,
    required Map<String, String> arguments,
  }) {
    final parts = <String>[binaryPath];
    switch (routine) {
      case 'batch_verify':
        parts.add('batch-verify');
        break;
      case 'key_backup':
        parts.add('backup-keys');
        break;
      case 'token_sweep':
        parts.add('sweep-tokens');
        break;
      default:
        throw ArgumentError('Unknown Zegel routine: $routine');
    }
    for (final entry in arguments.entries) {
      parts.add('--${entry.key}');
      parts.add(entry.value);
    }
    return crontabLine(
      schedule: schedule,
      command: parts.join(' '),
      description: 'Zegel $routine routine',
    );
  }

  static void _validateCronExpression(String expr) {
    final fields = expr.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw ArgumentError('Cron expression must have exactly 5 fields: "$expr"');
    }
  }
}

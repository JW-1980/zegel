import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('CronTemplate', () {
    test('presets map to expected cron expressions', () {
      expect(CronTemplate.preset('hourly'), '0 * * * *');
      expect(CronTemplate.preset('daily_midnight'), '0 0 * * *');
      expect(CronTemplate.preset('weekly_sunday'), '0 0 * * 0');
      expect(() => CronTemplate.preset('nope'), throwsArgumentError);
    });

    test('crontabLine resolves preset schedules and adds comment', () {
      final line = CronTemplate.crontabLine(
        schedule: 'daily_midnight',
        command: '/usr/local/bin/zegel verify /data',
        description: 'Nightly batch verify',
      );
      expect(line, contains('# Nightly batch verify'));
      expect(line, contains('0 0 * * * /usr/local/bin/zegel verify /data'));
    });

    test('crontabLine rejects malformed literal expressions', () {
      expect(
        () => CronTemplate.crontabLine(
          schedule: '* * * *',
          command: 'cmd',
        ),
        throwsArgumentError,
      );
    });

    test('environment lines precede the cron expression', () {
      final line = CronTemplate.crontabLine(
        schedule: '0 3 * * *',
        command: 'cmd',
        environment: {'ZEGEL_KEY_FILE': '/etc/zegel.key'},
      );
      final lines = line.split('\n');
      expect(lines.first, 'ZEGEL_KEY_FILE=/etc/zegel.key');
      expect(lines.last, contains('0 3 * * * cmd'));
    });

    test('systemdUnits builds valid unit bodies', () {
      final units = CronTemplate.systemdUnits(
        unitName: 'zegel-verify',
        description: 'Zegel nightly verify',
        execStart: '/usr/local/bin/zegel verify /data',
        onCalendar: 'daily',
        workingDirectory: '/data',
      );

      expect(units.service, contains('[Service]'));
      expect(units.service,
          contains('ExecStart=/usr/local/bin/zegel verify /data'));
      expect(units.service, contains('WorkingDirectory=/data'));

      expect(units.timer, contains('[Timer]'));
      expect(units.timer, contains('OnCalendar=daily'));
      expect(units.timer, contains('Unit=zegel-verify.service'));
    });

    test('zegelRoutine builds crontab for known routines', () {
      final line = CronTemplate.zegelRoutine(
        routine: 'batch_verify',
        schedule: 'daily_three_am',
        binaryPath: '/usr/local/bin/zegel',
        arguments: {'folder': '/data', 'key-file': '/etc/zegel.key'},
      );
      expect(line, contains('/usr/local/bin/zegel batch-verify'));
      expect(line, contains('--folder /data'));
      expect(line, contains('--key-file /etc/zegel.key'));
    });
  });
}

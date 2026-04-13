import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('UsageAnalytics', () {
    test('disabled collector is a no-op', () {
      final a = UsageAnalytics(enabled: false);
      a.recordCommand('seal');
      a.recordScreen('home');
      a.recordAlgorithm('AES-256-GCM');
      a.recordFileSealed(1024);
      expect(a.commandCounts, isEmpty);
      expect(a.screenCounts, isEmpty);
      expect(a.algorithmCounts, isEmpty);
      expect(a.totalFilesSealed, 0);
    });

    test('enabled collector aggregates counts', () {
      final a = UsageAnalytics(enabled: true);
      a.recordCommand('seal');
      a.recordCommand('seal');
      a.recordCommand('verify');
      a.recordScreen('home');
      a.recordAlgorithm('AES-256-GCM');
      a.recordFileSealed(1000);
      a.recordFileSealed(3000);

      expect(a.commandCounts, {'seal': 2, 'verify': 1});
      expect(a.screenCounts, {'home': 1});
      expect(a.algorithmCounts, {'AES-256-GCM': 1});
      expect(a.totalFilesSealed, 2);
      expect(a.totalBytesSealed, 4000);
      expect(a.averageFileSizeBytes, 2000);
    });

    test('topCommands returns descending order', () {
      final a = UsageAnalytics(enabled: true);
      a.recordCommand('seal');
      a.recordCommand('seal');
      a.recordCommand('seal');
      a.recordCommand('verify');
      a.recordCommand('attest');
      a.recordCommand('attest');

      final top = a.topCommands(limit: 2);
      expect(top.length, 2);
      expect(top.first.key, 'seal');
      expect(top.first.value, 3);
      expect(top[1].key, 'attest');
      expect(top[1].value, 2);
    });

    test('encode/decodeJson round trip', () {
      final a = UsageAnalytics(enabled: true);
      a.recordCommand('seal');
      a.recordAlgorithm('Ed25519');
      a.recordFileSealed(2048);

      final encoded = a.encode();
      final restored = UsageAnalytics.decodeJson(encoded);
      expect(restored.enabled, isTrue);
      expect(restored.commandCounts, {'seal': 1});
      expect(restored.algorithmCounts, {'Ed25519': 1});
      expect(restored.totalFilesSealed, 1);
      expect(restored.totalBytesSealed, 2048);
    });

    test('reset clears everything', () {
      final a = UsageAnalytics(enabled: true);
      a.recordCommand('seal');
      a.reset();
      expect(a.commandCounts, isEmpty);
      expect(a.totalFilesSealed, 0);
    });
  });
}

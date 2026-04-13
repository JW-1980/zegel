import 'dart:convert';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ZegelWebhook', () {
    test('buildPayload includes event type and timestamp', () {
      final webhook = ZegelWebhook(
        url: Uri.parse('https://example.org/hook'),
        eventType: 'verify_succeeded',
      );
      final payload = webhook.buildPayload(
        {'file': 'report.zgl'},
        at: DateTime.utc(2026, 4, 12, 12, 0, 0),
      );
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded['event'], 'verify_succeeded');
      expect(decoded['timestamp'], '2026-04-12T12:00:00.000Z');
      expect(decoded['data'], {'file': 'report.zgl'});
    });

    test('signPayload produces a deterministic HMAC-SHA256', () {
      const secret = 'shh';
      final sig1 = ZegelWebhook.signPayload('hello', secret);
      final sig2 = ZegelWebhook.signPayload('hello', secret);
      expect(sig1, sig2);
      expect(sig1.length, 64);
      expect(sig1, matches(RegExp(r'^[0-9a-f]{64}$')));

      final sig3 = ZegelWebhook.signPayload('world', secret);
      expect(sig3, isNot(sig1));
    });
  });
}

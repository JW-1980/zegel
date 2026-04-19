import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// A synchronous prober that always reports the connection as online.
Future<bool> _alwaysOnline(String _) async => true;

/// A synchronous prober that always reports the connection as offline.
Future<bool> _alwaysOffline(String _) async => false;

/// A prober that throws an exception, simulating a network error.
Future<bool> _alwaysThrows(String endpoint) async =>
    throw Exception('Network error for $endpoint');

void main() {
  group('OfflineIndicator', () {
    group('initial state', () {
      test('starts in unknown state', () {
        final indicator = OfflineIndicator(
          endpoints: ['example.com'],
          prober: _alwaysOnline,
        );
        expect(indicator.state, ConnectivityState.unknown);
        indicator.close();
      });
    });

    group('probeOnce — always-online prober', () {
      test('returns online when prober returns true', () async {
        final indicator = OfflineIndicator(
          endpoints: ['example.com'],
          prober: _alwaysOnline,
        );
        final result = await indicator.probeOnce();
        expect(result, ConnectivityState.online);
        await indicator.close();
      });

      test('state is online after probeOnce returns online', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host1', 'host2'],
          prober: _alwaysOnline,
        );
        await indicator.probeOnce();
        expect(indicator.state, ConnectivityState.online);
        await indicator.close();
      });

      test('returns online with multiple endpoints (first hit short-circuits)', () async {
        var callCount = 0;
        Future<bool> countingProber(String _) async {
          callCount++;
          return true;
        }

        final indicator = OfflineIndicator(
          endpoints: ['a', 'b', 'c'],
          prober: countingProber,
        );
        await indicator.probeOnce();
        // Should stop probing after the first success.
        expect(callCount, 1);
        await indicator.close();
      });
    });

    group('probeOnce — always-offline prober', () {
      test('returns offline when prober returns false for all endpoints', () async {
        final indicator = OfflineIndicator(
          endpoints: ['dead.example', 'also.dead'],
          prober: _alwaysOffline,
        );
        final result = await indicator.probeOnce();
        expect(result, ConnectivityState.offline);
        await indicator.close();
      });

      test('state is offline after probeOnce returns offline', () async {
        final indicator = OfflineIndicator(
          endpoints: ['dead.example'],
          prober: _alwaysOffline,
        );
        await indicator.probeOnce();
        expect(indicator.state, ConnectivityState.offline);
        await indicator.close();
      });

      test('probes all endpoints before giving up', () async {
        var callCount = 0;
        Future<bool> countingOffline(String _) async {
          callCount++;
          return false;
        }

        final indicator = OfflineIndicator(
          endpoints: ['a', 'b', 'c'],
          prober: countingOffline,
        );
        await indicator.probeOnce();
        expect(callCount, 3);
        await indicator.close();
      });
    });

    group('probeOnce — throwing prober', () {
      test('treats exception as offline when only endpoint throws', () async {
        final indicator = OfflineIndicator(
          endpoints: ['bad.host'],
          prober: _alwaysThrows,
        );
        final result = await indicator.probeOnce();
        expect(result, ConnectivityState.offline);
        await indicator.close();
      });

      test('falls through to next endpoint when first throws', () async {
        final probers = <String, Future<bool> Function(String)>{
          'host1': _alwaysThrows,
          'host2': _alwaysOnline,
        };
        Future<bool> routingProber(String endpoint) =>
            (probers[endpoint] ?? _alwaysOffline)(endpoint);

        final indicator = OfflineIndicator(
          endpoints: ['host1', 'host2'],
          prober: routingProber,
        );
        final result = await indicator.probeOnce();
        expect(result, ConnectivityState.online);
        await indicator.close();
      });

      test('all endpoints throwing results in offline state', () async {
        final indicator = OfflineIndicator(
          endpoints: ['a', 'b'],
          prober: _alwaysThrows,
        );
        final result = await indicator.probeOnce();
        expect(result, ConnectivityState.offline);
        await indicator.close();
      });
    });

    group('probeOnce — empty endpoint list', () {
      test('returns offline with no endpoints configured', () async {
        final indicator = OfflineIndicator(
          endpoints: [],
          prober: _alwaysOnline,
        );
        final result = await indicator.probeOnce();
        expect(result, ConnectivityState.offline);
        await indicator.close();
      });
    });

    group('stream — state transitions', () {
      test('emits online event when state changes from unknown to online', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: _alwaysOnline,
        );
        final received = <ConnectivityState>[];
        final sub = indicator.stream.listen(received.add);
        await indicator.probeOnce();
        await sub.cancel();
        await indicator.close();
        expect(received, contains(ConnectivityState.online));
      });

      test('emits offline event when state changes from unknown to offline', () async {
        final indicator = OfflineIndicator(
          endpoints: ['dead'],
          prober: _alwaysOffline,
        );
        final received = <ConnectivityState>[];
        final sub = indicator.stream.listen(received.add);
        await indicator.probeOnce();
        await sub.cancel();
        await indicator.close();
        expect(received, contains(ConnectivityState.offline));
      });

      test('does not emit duplicate events when state is unchanged', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: _alwaysOnline,
        );
        final received = <ConnectivityState>[];
        final sub = indicator.stream.listen(received.add);
        await indicator.probeOnce();
        await indicator.probeOnce(); // same state — should not re-emit
        await sub.cancel();
        await indicator.close();
        expect(received.length, 1);
      });

      test('emits transition when state flips from online to offline', () async {
        var online = true;
        Future<bool> flippingProber(String _) async => online;

        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: flippingProber,
        );
        final received = <ConnectivityState>[];
        final sub = indicator.stream.listen(received.add);

        await indicator.probeOnce(); // online
        online = false;
        await indicator.probeOnce(); // offline — state flips

        await sub.cancel();
        await indicator.close();

        expect(received, [ConnectivityState.online, ConnectivityState.offline]);
      });

      test('stream is a broadcast stream (multiple listeners allowed)', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: _alwaysOnline,
        );
        final a = <ConnectivityState>[];
        final b = <ConnectivityState>[];
        final subA = indicator.stream.listen(a.add);
        final subB = indicator.stream.listen(b.add);
        await indicator.probeOnce();
        await subA.cancel();
        await subB.cancel();
        await indicator.close();
        expect(a, containsAll([ConnectivityState.online]));
        expect(b, containsAll([ConnectivityState.online]));
      });
    });

    group('start / stop', () {
      test('stop cancels the polling timer without error', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          pollInterval: const Duration(hours: 1), // long enough not to fire
          prober: _alwaysOnline,
        );
        indicator.start();
        expect(indicator.stop, returnsNormally);
        await indicator.close();
      });

      test('calling stop before start is safe', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: _alwaysOnline,
        );
        expect(indicator.stop, returnsNormally);
        await indicator.close();
      });
    });

    group('close', () {
      test('close is safe to call when not started', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: _alwaysOnline,
        );
        await expectLater(indicator.close(), completes);
      });

      test('close is safe to call after stop', () async {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: _alwaysOnline,
        );
        indicator.start();
        indicator.stop();
        await expectLater(indicator.close(), completes);
      });
    });

    group('ConnectivityState enum', () {
      test('has exactly three values', () {
        expect(ConnectivityState.values.length, 3);
      });

      test('values are unknown, online, offline', () {
        expect(ConnectivityState.values, containsAll([
          ConnectivityState.unknown,
          ConnectivityState.online,
          ConnectivityState.offline,
        ]));
      });
    });

    group('endpoints property', () {
      test('stores the supplied endpoints list', () {
        final indicator = OfflineIndicator(
          endpoints: ['a.com', 'b.com'],
          prober: _alwaysOnline,
        );
        expect(indicator.endpoints, ['a.com', 'b.com']);
        indicator.close();
      });

      test('stores the poll interval', () {
        const interval = Duration(seconds: 60);
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          pollInterval: interval,
          prober: _alwaysOnline,
        );
        expect(indicator.pollInterval, interval);
        indicator.close();
      });

      test('default poll interval is 30 seconds', () {
        final indicator = OfflineIndicator(
          endpoints: ['host'],
          prober: _alwaysOnline,
        );
        expect(indicator.pollInterval, const Duration(seconds: 30));
        indicator.close();
      });
    });
  });
}

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('DashboardCatalog', () {
    test('default catalog exposes the shipped widgets', () {
      final catalog = DashboardCatalog();
      expect(catalog.allSpecs().length, DashboardCatalog.defaultSpecs.length);
      expect(catalog.lookup('key_health'), isNotNull);
    });

    test('visibleSpecs omits hidden widgets', () {
      final catalog = DashboardCatalog();
      catalog.setVisible('key_health', false);
      expect(catalog.visibleSpecs().any((s) => s.key == 'key_health'), isFalse);
      expect(catalog.allSpecs().any((s) => s.key == 'key_health'), isTrue);
    });

    test('reorder places explicit keys first', () {
      final catalog = DashboardCatalog();
      catalog.reorder(<String>['time_saved', 'key_health']);
      final visible = catalog.visibleSpecs();
      expect(visible.first.key, 'time_saved');
      expect(visible[1].key, 'key_health');
    });

    test('setVisible throws on unknown key', () {
      final catalog = DashboardCatalog();
      expect(() => catalog.setVisible('nonexistent', false), throwsStateError);
    });
  });
}

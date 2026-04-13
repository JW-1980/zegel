import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('FeatureRatings', () {
    test('rejects out-of-range star values', () {
      final r = FeatureRatings();
      expect(() => r.addRating('seal', stars: 0), throwsArgumentError);
      expect(() => r.addRating('seal', stars: 6), throwsArgumentError);
    });

    test('aggregates averages correctly', () {
      final r = FeatureRatings();
      r.addRating('seal', stars: 5);
      r.addRating('seal', stars: 3);
      r.addRating('verify', stars: 4);
      expect(r.averageFor('seal'), 4.0);
      expect(r.averageFor('verify'), 4.0);
      expect(r.averageFor('missing'), isNull);
      expect(r.totalRatings, 3);
    });

    test('ranked returns descending average order with tie-break', () {
      final r = FeatureRatings();
      r.addRating('seal', stars: 5);
      r.addRating('verify', stars: 5);
      r.addRating('verify', stars: 5);
      r.addRating('attest', stars: 4);

      final ranked = r.ranked();
      expect(ranked.first.feature, 'verify');
      expect(ranked[1].feature, 'seal');
      expect(ranked.last.feature, 'attest');
    });

    test('encode/decodeJson round trip', () {
      final r = FeatureRatings();
      r.addRating('seal', stars: 5, comment: 'great');
      final restored = FeatureRatings.decodeJson(r.encode());
      expect(restored.totalRatings, 1);
      expect(restored.averageFor('seal'), 5.0);
      expect(restored.ratingsFor('seal').first.comment, 'great');
    });
  });
}

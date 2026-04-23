import 'dart:convert';
import 'dart:io';

/// User feature ratings collection (improvement #40).
///
/// Collects 1-to-5 star ratings for individual features along with an
/// optional free-text comment. Designed for an in-app "how useful did you
/// find this feature?" workflow that feeds a local aggregate the developer
/// can inspect.
class FeatureRatings {
  FeatureRatings() : _ratings = {};

  final Map<String, List<FeatureRating>> _ratings;

  /// Adds a rating for [feature]. [stars] must be between 1 and 5.
  void addRating(
    String feature, {
    required int stars,
    String? comment,
    DateTime? at,
  }) {
    if (stars < 1 || stars > 5) {
      throw ArgumentError.value(stars, 'stars', 'must be in 1..5');
    }
    final rating = FeatureRating(
      stars: stars,
      comment: comment,
      at: (at ?? DateTime.now().toUtc()).toUtc(),
    );
    _ratings.putIfAbsent(feature, () => []).add(rating);
  }

  /// All features that have received at least one rating.
  Iterable<String> get features => _ratings.keys;

  /// All ratings for a single feature, newest last.
  List<FeatureRating> ratingsFor(String feature) =>
      List<FeatureRating>.unmodifiable(
        _ratings[feature] ?? const <FeatureRating>[],
      );

  /// Total rating count across all features.
  int get totalRatings => _ratings.values.fold<int>(0, (a, b) => a + b.length);

  /// Average star rating for [feature]. Returns `null` if there are none.
  double? averageFor(String feature) {
    final list = _ratings[feature];
    if (list == null || list.isEmpty) return null;
    final sum = list.fold<int>(0, (a, r) => a + r.stars);
    return sum / list.length;
  }

  /// Returns a rank-ordered list of features by their average rating,
  /// descending. Features tie-break on sample count (more samples first).
  List<FeatureRatingSummary> ranked() {
    final out = <FeatureRatingSummary>[];
    for (final entry in _ratings.entries) {
      if (entry.value.isEmpty) continue;
      final avg = averageFor(entry.key)!;
      out.add(
        FeatureRatingSummary(
          feature: entry.key,
          averageStars: avg,
          sampleSize: entry.value.length,
        ),
      );
    }
    out.sort((a, b) {
      final cmp = b.averageStars.compareTo(a.averageStars);
      if (cmp != 0) return cmp;
      return b.sampleSize.compareTo(a.sampleSize);
    });
    return out;
  }

  Map<String, dynamic> toJson() => {
        for (final e in _ratings.entries)
          e.key: e.value.map((r) => r.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static FeatureRatings decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final result = FeatureRatings();
    for (final entry in m.entries) {
      final list = (entry.value as List<dynamic>)
          .map((e) => FeatureRating.fromJson(e as Map<String, dynamic>))
          .toList();
      result._ratings[entry.key] = list;
    }
    return result;
  }

  void saveFile(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encode());
  }

  static FeatureRatings loadFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return FeatureRatings();
    return decodeJson(file.readAsStringSync());
  }
}

class FeatureRating {
  const FeatureRating({required this.stars, this.comment, required this.at});

  static FeatureRating fromJson(Map<String, dynamic> json) => FeatureRating(
        stars: (json['stars'] as num).toInt(),
        comment: json['comment'] as String?,
        at: DateTime.parse(json['at'] as String).toUtc(),
      );

  final int stars;
  final String? comment;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'stars': stars,
        if (comment != null) 'comment': comment,
        'at': at.toUtc().toIso8601String(),
      };
}

class FeatureRatingSummary {
  const FeatureRatingSummary({
    required this.feature,
    required this.averageStars,
    required this.sampleSize,
  });

  final String feature;
  final double averageStars;
  final int sampleSize;
}

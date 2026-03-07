import 'package:flutter/material.dart';

/// A color-coded classification level badge.
///
/// Displays a shield icon with the classification level text.
/// Color coding:
/// - PUBLIC: green
/// - INTERNAL: blue
/// - CONFIDENTIAL: yellow/amber
/// - SECRET: orange
/// - TOP_SECRET: red
class ClassificationBadge extends StatelessWidget {
  /// The classification level string.
  final String level;

  /// Whether to show the badge in a compact form.
  final bool compact;

  const ClassificationBadge({
    super.key,
    required this.level,
    this.compact = false,
  });

  Color _color() {
    switch (level.toUpperCase()) {
      case 'PUBLIC':
        return const Color(0xFF2E7D32); // green
      case 'INTERNAL':
        return const Color(0xFF1565C0); // blue
      case 'CONFIDENTIAL':
        return const Color(0xFFF9A825); // amber
      case 'SECRET':
        return const Color(0xFFE65100); // orange
      case 'TOP_SECRET':
        return const Color(0xFFC62828); // red
      default:
        return const Color(0xFF757575); // grey
    }
  }

  String _displayText() {
    switch (level.toUpperCase()) {
      case 'TOP_SECRET':
        return 'TOP SECRET';
      default:
        return level.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          _displayText(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            _displayText(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A large classification banner for display at the top of screens.
class ClassificationBanner extends StatelessWidget {
  final String level;

  const ClassificationBanner({super.key, required this.level});

  Color _color() {
    switch (level.toUpperCase()) {
      case 'PUBLIC':
        return const Color(0xFF2E7D32);
      case 'INTERNAL':
        return const Color(0xFF1565C0);
      case 'CONFIDENTIAL':
        return const Color(0xFFF9A825);
      case 'SECRET':
        return const Color(0xFFE65100);
      case 'TOP_SECRET':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFF757575);
    }
  }

  Color _textColor() {
    switch (level.toUpperCase()) {
      case 'CONFIDENTIAL':
        return Colors.black87;
      default:
        return Colors.white;
    }
  }

  String _displayText() {
    switch (level.toUpperCase()) {
      case 'TOP_SECRET':
        return 'TOP SECRET';
      default:
        return level.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final textColor = _textColor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            _displayText(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

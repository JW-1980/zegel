import 'package:flutter/material.dart';

/// A blocking progress overlay that covers the entire screen.
///
/// Prevents user interaction while a long-running operation is in progress.
/// Shows a centered spinner with an optional status message.
///
/// Usage:
/// ```dart
/// ProgressOverlay.show(context, message: 'Sealing file...');
/// try {
///   await doWork();
/// } finally {
///   ProgressOverlay.hide(context);
/// }
/// ```
class ProgressOverlay extends StatelessWidget {
  /// The message to display below the spinner.
  final String? message;

  const ProgressOverlay({super.key, this.message});

  /// Shows a blocking progress overlay on the given context.
  ///
  /// Call [hide] to dismiss it. The overlay blocks all user interaction
  /// until dismissed.
  static void show(BuildContext context, {String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => ProgressOverlay(message: message),
    );
  }

  /// Hides the progress overlay.
  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (message != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    message!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A skeleton loader widget that shows a shimmering animation
/// while content is loading.
///
/// Replaces traditional spinners for a more polished loading experience.
class SkeletonLoader extends StatefulWidget {
  /// Width of the skeleton element.
  final double width;

  /// Height of the skeleton element.
  final double height;

  /// Border radius of the skeleton element.
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 4,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A group of skeleton lines for simulating text content loading.
class SkeletonTextBlock extends StatelessWidget {
  /// Number of skeleton lines to show.
  final int lines;

  /// Spacing between lines.
  final double spacing;

  const SkeletonTextBlock({super.key, this.lines = 3, this.spacing = 8});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines, (i) {
        // Last line is shorter for realism.
        final width = i == lines - 1 ? 0.6 : 1.0;
        return Padding(
          padding: EdgeInsets.only(bottom: i < lines - 1 ? spacing : 0),
          child: FractionallySizedBox(
            widthFactor: width,
            child: const SkeletonLoader(height: 14),
          ),
        );
      }),
    );
  }
}

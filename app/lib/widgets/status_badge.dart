import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import '../services/zegel_service.dart';

/// A large, centered status badge that displays the verification result.
///
/// Three states:
/// - Valid: green checkmark with "INTACT" text
/// - Tampered: red X with "TAMPERED" text
/// - Expired: orange clock with "EXPIRED" text
class StatusBadge extends StatefulWidget {
  /// The verification status to display.
  final ZegelStatus status;

  /// Whether to animate the state change.
  final bool animate;

  const StatusBadge({super.key, required this.status, this.animate = true});

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status && widget.animate) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _statusColor() {
    switch (widget.status) {
      case ZegelStatus.valid:
        return const Color(0xFF2E7D32);
      case ZegelStatus.tampered:
        return const Color(0xFFC62828);
      case ZegelStatus.expired:
        return const Color(0xFFE65100);
    }
  }

  IconData _statusIcon() {
    switch (widget.status) {
      case ZegelStatus.valid:
        return Icons.verified;
      case ZegelStatus.tampered:
        return Icons.dangerous;
      case ZegelStatus.expired:
        return Icons.schedule;
    }
  }

  String _statusText(AppLocalizations l10n) {
    switch (widget.status) {
      case ZegelStatus.valid:
        return l10n.verifyValid;
      case ZegelStatus.tampered:
        return l10n.verifyTampered;
      case ZegelStatus.expired:
        return l10n.verifyExpired;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final color = _statusColor();

    return AnimatedBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.1),
                    border: Border.all(color: color, width: 3),
                  ),
                  child: Icon(_statusIcon(), size: 64, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusText(l10n),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Simple animated builder helper.
class AnimatedBuilder extends StatelessWidget {
  final Listenable listenable;
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required this.listenable,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: listenable, builder: builder);
  }
}

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';

/// The detected action based on the dropped file.
enum DropAction {
  /// File should be sealed (not a .zgl file).
  seal,

  /// File should be verified (is a .zgl file).
  verify,
}

/// Result of a drag and drop operation.
class DropResult {
  final String filePath;
  final DropAction action;

  const DropResult({required this.filePath, required this.action});
}

/// A drag-and-drop zone widget for accepting files.
///
/// Provides visual feedback on drag hover and auto-detects
/// whether the dropped file should be sealed or verified
/// based on its extension.
class DropZone extends StatefulWidget {
  /// Called when a file is dropped into the zone.
  final ValueChanged<DropResult> onFileDropped;

  /// Called when the user taps the zone to open a file picker.
  final VoidCallback? onTap;

  const DropZone({
    super.key,
    required this.onFileDropped,
    this.onTap,
  });

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  DropAction _detectAction(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    return extension == 'zgl' ? DropAction.verify : DropAction.seal;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDragging = true);
        _pulseController.repeat(reverse: true);
      },
      onDragExited: (_) {
        setState(() => _isDragging = false);
        _pulseController.stop();
        _pulseController.reset();
      },
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _pulseController.stop();
        _pulseController.reset();

        if (details.files.isNotEmpty) {
          final filePath = details.files.first.path;
          final action = _detectAction(filePath);
          widget.onFileDropped(DropResult(filePath: filePath, action: action));
        }
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isDragging ? _pulseAnimation.value : 1.0,
              child: child,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            constraints: const BoxConstraints(
              minHeight: 220,
              maxHeight: 300,
            ),
            decoration: BoxDecoration(
              color: _isDragging
                  ? colorScheme.primary.withOpacity(0.08)
                  : colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isDragging
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.3),
                width: _isDragging ? 3 : 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isDragging ? Icons.file_download : Icons.cloud_upload_outlined,
                    size: 64,
                    color: _isDragging
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.dropZoneHint,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: _isDragging
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (!_isDragging)
                    Text(
                      'or tap to browse',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A helper widget that rebuilds when an animation changes.
/// Used for the pulse effect on the drop zone.
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget? child;
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: animation,
      builder: builder,
      child: child,
    );
  }
}

/// Inner animated builder using the framework's AnimatedWidget pattern.
class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

import 'package:flutter/material.dart';

/// Status of a single workflow step.
enum WorkflowStepStatus {
  pending,
  inProgress,
  completed,
  failed,
}

/// Data model for a workflow step.
class WorkflowStep {
  final String title;
  final String description;
  final WorkflowStepStatus status;

  const WorkflowStep({
    required this.title,
    required this.description,
    required this.status,
  });

  WorkflowStep copyWith({
    String? title,
    String? description,
    WorkflowStepStatus? status,
  }) {
    return WorkflowStep(
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
    );
  }
}

/// A stepper widget for multi-step workflows.
///
/// Shows numbered steps with status indicators (pending, in progress,
/// completed, failed). Each step has a title and description.
class WorkflowStepperWidget extends StatelessWidget {
  /// The list of workflow steps.
  final List<WorkflowStep> steps;

  /// The currently active step index.
  final int currentStep;

  /// Optional callback when a step's action button is pressed.
  final void Function(int index)? onStepAction;

  /// Optional action button labels per step.
  final Map<int, String>? actionLabels;

  const WorkflowStepperWidget({
    super.key,
    required this.steps,
    this.currentStep = 0,
    this.onStepAction,
    this.actionLabels,
  });

  Color _statusColor(WorkflowStepStatus status) {
    switch (status) {
      case WorkflowStepStatus.pending:
        return const Color(0xFF9E9E9E);
      case WorkflowStepStatus.inProgress:
        return const Color(0xFF1565C0);
      case WorkflowStepStatus.completed:
        return const Color(0xFF2E7D32);
      case WorkflowStepStatus.failed:
        return const Color(0xFFC62828);
    }
  }

  IconData _statusIcon(WorkflowStepStatus status) {
    switch (status) {
      case WorkflowStepStatus.pending:
        return Icons.radio_button_unchecked;
      case WorkflowStepStatus.inProgress:
        return Icons.play_circle;
      case WorkflowStepStatus.completed:
        return Icons.check_circle;
      case WorkflowStepStatus.failed:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final color = _statusColor(step.status);
        final isLast = index == steps.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step number and line
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    // Step indicator circle
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Center(
                        child: step.status == WorkflowStepStatus.pending
                            ? Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              )
                            : Icon(
                                _statusIcon(step.status),
                                size: 18,
                                color: color,
                              ),
                      ),
                    ),
                    // Connecting line
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          color: index < currentStep
                              ? const Color(0xFF2E7D32).withValues(alpha: 0.5)
                              : theme.colorScheme.outline
                                  .withValues(alpha: 0.2),
                        ),
                      ),
                  ],
                ),
              ),
              // Step content
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isLast ? 0 : 16,
                    left: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        step.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: step.status == WorkflowStepStatus.pending
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (step.status == WorkflowStepStatus.inProgress) ...[
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 2,
                          child: LinearProgressIndicator(
                            backgroundColor: color.withValues(alpha: 0.2),
                            color: color,
                          ),
                        ),
                      ],
                      if (onStepAction != null &&
                          actionLabels != null &&
                          actionLabels!.containsKey(index) &&
                          step.status != WorkflowStepStatus.completed) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => onStepAction!(index),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: color,
                            side: BorderSide(color: color),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            actionLabels![index]!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

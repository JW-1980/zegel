/// Web-based first-launch setup wizard state machine (improvement #111).
///
/// Framework-agnostic sequence of steps that the Flutter web build or a
/// Laravel admin page can walk through on first launch: choose a
/// database, configure the TSA URL, create the first admin key, etc.
///
/// The wizard tracks which steps are complete and yields the next one
/// to show, so the UI only has to render a single step at a time.
class WebSetupWizard {
  WebSetupWizard({List<SetupStep>? steps})
    : _steps = List<SetupStep>.unmodifiable(steps ?? defaultSteps),
      _completed = <String>{},
      _answers = <String, Object?>{};

  /// Default set of steps shipped with Zegel.
  static const List<SetupStep> defaultSteps = <SetupStep>[
    SetupStep(
      id: 'welcome',
      title: 'Welcome to Zegel',
      description:
          'A one-time setup configures the server. Takes about a '
          'minute.',
      requiredAnswer: null,
    ),
    SetupStep(
      id: 'database',
      title: 'Configure storage',
      description: 'Choose where Zegel stores its metadata.',
      requiredAnswer: 'database_dsn',
    ),
    SetupStep(
      id: 'tsa',
      title: 'Timestamp authority',
      description: 'Optionally configure an RFC 3161 timestamp server.',
      requiredAnswer: null,
    ),
    SetupStep(
      id: 'admin-key',
      title: 'Create first admin key',
      description: 'Generate a master key that can rotate operator access.',
      requiredAnswer: 'admin_key_fingerprint',
    ),
    SetupStep(
      id: 'finish',
      title: 'All done',
      description: 'You can revisit these settings from the admin panel.',
      requiredAnswer: null,
    ),
  ];

  final List<SetupStep> _steps;
  final Set<String> _completed;
  final Map<String, Object?> _answers;

  /// Every step in the wizard.
  List<SetupStep> get steps => _steps;

  /// Current step — the first incomplete entry, or null when the
  /// wizard is done.
  SetupStep? get currentStep {
    for (final step in _steps) {
      if (!_completed.contains(step.id)) return step;
    }
    return null;
  }

  /// True when every step has been marked completed.
  bool get isComplete => _completed.length == _steps.length;

  /// Percentage complete in [0.0, 1.0].
  double get progress =>
      _steps.isEmpty ? 1.0 : _completed.length / _steps.length;

  /// Records an answer for a step. Only validates that the step
  /// exists. A separate call to [complete] is required to advance.
  void answer(String stepId, Object? value) {
    if (!_steps.any((s) => s.id == stepId)) {
      throw StateError('Unknown step: $stepId');
    }
    _answers[stepId] = value;
  }

  /// Retrieves a previously recorded answer.
  Object? answerFor(String stepId) => _answers[stepId];

  /// Marks the step complete. Throws [StateError] when the step
  /// requires an answer that has not been provided.
  void complete(String stepId) {
    final step = _steps.firstWhere(
      (s) => s.id == stepId,
      orElse: () => throw StateError('Unknown step: $stepId'),
    );
    if (step.requiredAnswer != null && _answers[stepId] == null) {
      throw StateError(
        'Step $stepId requires an answer for "${step.requiredAnswer}"',
      );
    }
    _completed.add(stepId);
  }

  /// Rolls back a completed step so the user can revisit it.
  void reopen(String stepId) {
    _completed.remove(stepId);
  }

  /// Resets the whole wizard.
  void reset() {
    _completed.clear();
    _answers.clear();
  }
}

class SetupStep {
  const SetupStep({
    required this.id,
    required this.title,
    required this.description,
    this.requiredAnswer,
  });

  final String id;
  final String title;
  final String description;

  /// Name of the answer key this step requires. `null` means the step
  /// is informational only and can be completed without an answer.
  final String? requiredAnswer;
}

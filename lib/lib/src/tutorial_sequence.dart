/// Guided tutorial sequence (improvement #15).
///
/// Defines a small finite-state machine for multi-step user tutorials:
/// welcome → pick-file → enter-key → seal → done. The host UI binds
/// events ("user clicked next", "user completed step X") to the
/// sequence, and the sequence decides what to show next.
class TutorialSequence {

  /// Builds the default introduction sequence for new users.
  factory TutorialSequence.introduction() {
    return TutorialSequence(const <TutorialStep>[
      TutorialStep(
        id: 'welcome',
        title: 'Welcome to Zegel',
        description:
            'Zegel wraps any file in a tamper-proof container so it cannot '
            'be modified without detection. This short tour walks you through '
            'your first seal.',
      ),
      TutorialStep(
        id: 'pick-file',
        title: 'Pick a file to seal',
        description:
            'Drag a file onto the drop zone or use the Pick File button. '
            'Any file type will work.',
      ),
      TutorialStep(
        id: 'enter-key',
        title: 'Provide a master key',
        description:
            'You can either paste an existing 64-character hex key or press '
            'Generate to create a cryptographically random one.',
      ),
      TutorialStep(
        id: 'seal',
        title: 'Seal it',
        description:
            'Press Seal. Zegel computes a Merkle tree over the file, derives '
            'per-block encryption keys from it, and writes the result to a '
            'new `.zgl` file.',
      ),
      TutorialStep(
        id: 'verify',
        title: 'Verify your seal',
        description:
            'Drop the newly-sealed file back onto the drop zone to verify. '
            'A successful verification proves that not a single byte was '
            'modified since sealing.',
      ),
      TutorialStep(
        id: 'done',
        title: "You're done!",
        description:
            'Explore the drawer for advanced features: redaction, split-key, '
            'attestation, and more. Tooltips on every field explain what '
            'each cryptographic term means.',
      ),
    ]);
  }
  TutorialSequence(this.steps)
      : assert(steps.isNotEmpty, 'At least one step is required');

  /// The ordered list of steps.
  final List<TutorialStep> steps;

  int _current = 0;
  bool _finished = false;

  /// The current step, or null when the sequence has finished.
  TutorialStep? get current => _finished ? null : steps[_current];

  /// The zero-based index of the current step.
  int get currentIndex => _current;

  /// Whether the sequence has finished.
  bool get isFinished => _finished;

  /// Whether there is a previous step.
  bool get canGoBack => !_finished && _current > 0;

  /// Whether there is a next step.
  bool get canGoForward => !_finished && _current < steps.length - 1;

  /// Advances to the next step. Marks the sequence as finished if the
  /// current step is the last one. Returns the step now active, or
  /// null when the sequence has finished.
  TutorialStep? next() {
    if (_finished) return null;
    if (_current >= steps.length - 1) {
      _finished = true;
      return null;
    }
    _current += 1;
    return steps[_current];
  }

  /// Goes back to the previous step. Returns null if already at the
  /// first step. Resets the finished flag if the sequence had ended.
  TutorialStep? back() {
    if (_finished) {
      _finished = false;
      return steps[_current];
    }
    if (_current == 0) return null;
    _current -= 1;
    return steps[_current];
  }

  /// Resets the sequence to the first step.
  void reset() {
    _current = 0;
    _finished = false;
  }

  /// Ends the tutorial immediately (e.g. user clicked "Skip").
  void skip() {
    _finished = true;
  }
}

class TutorialStep {
  const TutorialStep({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;
}

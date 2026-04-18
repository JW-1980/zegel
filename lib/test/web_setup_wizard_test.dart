import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('WebSetupWizard', () {
    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    // Default steps: welcome, database(required), tsa, admin-key(required), finish
    WebSetupWizard _freshWizard() => WebSetupWizard();

    // A minimal two-step wizard for tests that need a simpler setup.
    WebSetupWizard _twoStepWizard() => WebSetupWizard(
      steps: [
        const SetupStep(
          id: 'step-a',
          title: 'Step A',
          description: 'No answer needed.',
          requiredAnswer: null,
        ),
        const SetupStep(
          id: 'step-b',
          title: 'Step B',
          description: 'Requires an answer.',
          requiredAnswer: 'some_key',
        ),
      ],
    );

    // -----------------------------------------------------------------------
    // Initial state
    // -----------------------------------------------------------------------
    group('initial state', () {
      test('currentStep is the first step (welcome)', () {
        final wizard = _freshWizard();
        expect(wizard.currentStep, isNotNull);
        expect(wizard.currentStep!.id, 'welcome');
      });

      test('isComplete is false at start', () {
        expect(_freshWizard().isComplete, isFalse);
      });

      test('progress is 0.0 at start', () {
        expect(_freshWizard().progress, 0.0);
      });

      test('steps list has the default 5 entries', () {
        expect(_freshWizard().steps.length, 5);
      });

      test('steps list is unmodifiable', () {
        final wizard = _freshWizard();
        // Use clear() rather than add(null): the latter throws a TypeError
        // (null is not a SetupStep) before reaching the unmodifiable guard.
        expect(wizard.steps.clear, throwsUnsupportedError);
      });

      test('no answers stored initially', () {
        final wizard = _freshWizard();
        expect(wizard.answerFor('welcome'), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // complete (informational / no requiredAnswer)
    // -----------------------------------------------------------------------
    group('complete – informational step', () {
      test('completing the welcome step advances currentStep to database', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        expect(wizard.currentStep!.id, 'database');
      });

      test('progress increases after completing a step', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        expect(wizard.progress, greaterThan(0.0));
      });

      test(
        'completing all informational steps leaves the wizard at the first required step',
        () {
          final wizard = _twoStepWizard();
          wizard.complete('step-a');
          expect(wizard.currentStep!.id, 'step-b');
        },
      );
    });

    // -----------------------------------------------------------------------
    // answer + complete (requiredAnswer steps)
    // -----------------------------------------------------------------------
    group('answer and complete – required answer step', () {
      test('complete throws StateError when required answer is missing', () {
        final wizard = _freshWizard();
        wizard.complete('welcome'); // advance past welcome
        expect(() => wizard.complete('database'), throwsA(isA<StateError>()));
      });

      test('complete succeeds after providing the required answer', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        wizard.answer('database', 'postgres://localhost/zegel');
        expect(() => wizard.complete('database'), returnsNormally);
      });

      test('currentStep advances past a required step once completed', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        wizard.answer('database', 'sqlite:///tmp/zegel.db');
        wizard.complete('database');
        expect(wizard.currentStep!.id, 'tsa');
      });

      test('answerFor returns the previously stored answer', () {
        final wizard = _freshWizard();
        wizard.answer('database', 'my_dsn');
        expect(wizard.answerFor('database'), 'my_dsn');
      });

      test('answer overwrites a previous answer for the same step', () {
        final wizard = _freshWizard();
        wizard.answer('database', 'first');
        wizard.answer('database', 'second');
        expect(wizard.answerFor('database'), 'second');
      });

      test('answer throws StateError for an unknown step id', () {
        final wizard = _freshWizard();
        expect(
          () => wizard.answer('nonexistent', 'value'),
          throwsA(isA<StateError>()),
        );
      });

      test('complete throws StateError for an unknown step id', () {
        final wizard = _freshWizard();
        expect(
          () => wizard.complete('nonexistent'),
          throwsA(isA<StateError>()),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Full walk-through to isComplete
    // -----------------------------------------------------------------------
    group('full completion', () {
      void _completeAll(WebSetupWizard wizard) {
        wizard.complete('welcome');
        wizard.answer('database', 'postgres://localhost/zegel');
        wizard.complete('database');
        wizard.complete('tsa');
        wizard.answer(
          'admin-key',
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        );
        wizard.complete('admin-key');
        wizard.complete('finish');
      }

      test('isComplete is true after all steps are done', () {
        final wizard = _freshWizard();
        _completeAll(wizard);
        expect(wizard.isComplete, isTrue);
      });

      test('currentStep is null when complete', () {
        final wizard = _freshWizard();
        _completeAll(wizard);
        expect(wizard.currentStep, isNull);
      });

      test('progress is 1.0 when all steps are complete', () {
        final wizard = _freshWizard();
        _completeAll(wizard);
        expect(wizard.progress, closeTo(1.0, 1e-9));
      });
    });

    // -----------------------------------------------------------------------
    // progress ratio
    // -----------------------------------------------------------------------
    group('progress ratio', () {
      test('progress is 0.2 after completing 1 of 5 default steps', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        expect(wizard.progress, closeTo(1 / 5, 1e-9));
      });

      test('progress is 0.4 after completing 2 of 5 default steps', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        wizard.answer('database', 'dsn');
        wizard.complete('database');
        expect(wizard.progress, closeTo(2 / 5, 1e-9));
      });

      test('progress for a custom two-step wizard is 0.5 after first step', () {
        final wizard = _twoStepWizard();
        wizard.complete('step-a');
        expect(wizard.progress, closeTo(0.5, 1e-9));
      });
    });

    // -----------------------------------------------------------------------
    // reset
    // -----------------------------------------------------------------------
    group('reset', () {
      test('reset clears completed steps', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        wizard.reset();
        expect(wizard.currentStep!.id, 'welcome');
      });

      test('reset clears stored answers', () {
        final wizard = _freshWizard();
        wizard.answer('database', 'value');
        wizard.reset();
        expect(wizard.answerFor('database'), isNull);
      });

      test('progress returns to 0.0 after reset', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        wizard.reset();
        expect(wizard.progress, 0.0);
      });

      test('isComplete returns false after reset', () {
        final wizard = _twoStepWizard();
        wizard.complete('step-a');
        wizard.answer('step-b', 'val');
        wizard.complete('step-b');
        wizard.reset();
        expect(wizard.isComplete, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // reopen
    // -----------------------------------------------------------------------
    group('reopen', () {
      test('reopen makes a completed step the current step again', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        // Reopen welcome; it becomes incomplete again.
        wizard.reopen('welcome');
        expect(wizard.currentStep!.id, 'welcome');
      });

      test('progress decreases after reopening a step', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        final progressBefore = wizard.progress;
        wizard.reopen('welcome');
        expect(wizard.progress, lessThan(progressBefore));
      });

      test('reopening a step that was never completed is a no-op', () {
        final wizard = _freshWizard();
        // Should not throw.
        expect(() => wizard.reopen('welcome'), returnsNormally);
        expect(wizard.currentStep!.id, 'welcome');
      });
    });

    // -----------------------------------------------------------------------
    // skip (informational step — no required answer — can be completed directly)
    // -----------------------------------------------------------------------
    group('skip (completing optional steps without an answer)', () {
      test('tsa step can be completed without providing an answer', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        wizard.answer('database', 'dsn');
        wizard.complete('database');
        // tsa has no requiredAnswer — should succeed without answer().
        expect(() => wizard.complete('tsa'), returnsNormally);
      });

      test('finish step can be completed without an answer', () {
        final wizard = _freshWizard();
        wizard.complete('welcome');
        wizard.answer('database', 'dsn');
        wizard.complete('database');
        wizard.complete('tsa');
        wizard.answer('admin-key', 'fp');
        wizard.complete('admin-key');
        expect(() => wizard.complete('finish'), returnsNormally);
        expect(wizard.isComplete, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // SetupStep data class
    // -----------------------------------------------------------------------
    group('SetupStep', () {
      test('stores id, title, description, and requiredAnswer', () {
        const step = SetupStep(
          id: 'test',
          title: 'Test Step',
          description: 'A description.',
          requiredAnswer: 'key_name',
        );
        expect(step.id, 'test');
        expect(step.title, 'Test Step');
        expect(step.description, 'A description.');
        expect(step.requiredAnswer, 'key_name');
      });

      test('requiredAnswer defaults to null', () {
        const step = SetupStep(id: 's', title: 'S', description: 'D');
        expect(step.requiredAnswer, isNull);
      });
    });

    // -----------------------------------------------------------------------
    // Empty wizard edge case
    // -----------------------------------------------------------------------
    group('empty wizard', () {
      test('isComplete is true for a wizard with no steps', () {
        final wizard = WebSetupWizard(steps: []);
        expect(wizard.isComplete, isTrue);
      });

      test('progress is 1.0 for a wizard with no steps', () {
        final wizard = WebSetupWizard(steps: []);
        expect(wizard.progress, 1.0);
      });

      test('currentStep is null for a wizard with no steps', () {
        final wizard = WebSetupWizard(steps: []);
        expect(wizard.currentStep, isNull);
      });
    });
  });
}

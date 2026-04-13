import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('TutorialSequence', () {
    test('next advances through the steps', () {
      final seq = TutorialSequence.introduction();
      final first = seq.current;
      expect(first, isNotNull);
      expect(first!.id, 'welcome');
      seq.next();
      expect(seq.current!.id, 'pick-file');
    });

    test('finishes after the last step', () {
      final seq = TutorialSequence.introduction();
      while (!seq.isFinished) {
        seq.next();
      }
      expect(seq.current, isNull);
      expect(seq.isFinished, isTrue);
    });

    test('back revives a finished sequence', () {
      final seq = TutorialSequence.introduction();
      while (!seq.isFinished) {
        seq.next();
      }
      seq.back();
      expect(seq.isFinished, isFalse);
    });

    test('reset returns to the first step', () {
      final seq = TutorialSequence.introduction();
      seq.next();
      seq.next();
      seq.reset();
      expect(seq.currentIndex, 0);
      expect(seq.canGoBack, isFalse);
    });

    test('skip ends the sequence', () {
      final seq = TutorialSequence.introduction();
      seq.skip();
      expect(seq.isFinished, isTrue);
      expect(seq.current, isNull);
    });
  });
}

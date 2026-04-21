import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('Anonymizer', () {
    test('scrub replaces emails, IPs, and paths', () {
      final anon = Anonymizer.fromHex('deadbeefdeadbeef');
      const input =
          'Contact alice@example.com from 192.168.1.42 (/home/alice/secrets.txt)';
      final scrubbed = anon.scrub(input);
      expect(scrubbed, isNot(contains('alice@example.com')));
      expect(scrubbed, isNot(contains('192.168.1.42')));
      expect(scrubbed, isNot(contains('/home/alice/secrets.txt')));
      expect(scrubbed, contains('<email:'));
      expect(scrubbed, contains('<ip:'));
      expect(scrubbed, contains('<path:'));
    });

    test('scrubStackTrace preserves line count', () {
      final anon = Anonymizer.fromHex('01020304');
      const stack = '#0 main\n#1 run\n#2 boot';
      final scrubbed = anon.scrubStackTrace(stack);
      expect(scrubbed.trim().split('\n').length, 3);
    });

    test('deterministic with same salt', () {
      final a = Anonymizer.fromHex('abcdef01');
      final b = Anonymizer.fromHex('abcdef01');
      expect(a.hash('alice'), b.hash('alice'));
      expect(a.hash('alice'), isNot(b.hash('bob')));
    });

    test('random salts differ across instances', () {
      final a = Anonymizer.random();
      final b = Anonymizer.random();
      // Extremely unlikely to collide (16 random bytes).
      expect(a.saltHex(), isNot(b.saltHex()));
    });
  });
}

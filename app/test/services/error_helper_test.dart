import 'package:flutter_test/flutter_test.dart';
import 'package:zegel_app/services/error_helper.dart';

void main() {
  test('ErrorHelper formats correctly', () {
    final msg = ErrorHelper.humanize(Exception('Master key must be exactly 32 bytes'));
    expect(msg.title, 'Invalid Master Key');
    expect(msg.description, contains('master key must be exactly 32 bytes'));
  });
}

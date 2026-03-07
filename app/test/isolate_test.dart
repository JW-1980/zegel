import 'package:flutter_test/flutter_test.dart';
import 'package:zegel_app/services/zegel_service.dart';

void main() {
  test('ZegelService.verify runs successfully for non-existent file', () async {
    final service = ZegelService();
    // This file doesn't exist, should return tampered status
    final result = await service.verify('nonexistent.zgl', '001122');
    expect(result.status, equals(ZegelStatus.tampered));
    expect(result.message, equals('File does not exist'));
  });
}

import 'dart:io';
import 'package:test/test.dart';
import 'app/lib/services/zegel_service.dart';
import 'package:zegel/zegel.dart' as zegel;

void main() {
  test('batchVerify baseline benchmark', () async {
    final service = ZegelService();
    // Setup dummy test files
    final dir = Directory('test_benchmark_tmp');
    await dir.create();

    final files = <String>[];
    for (int i = 0; i < 100; i++) {
      final f = File('${dir.path}/test_$i.txt');
      await f.writeAsBytes(List.generate(1024, (index) => index % 256));
      files.add(f.path);
    }

    final stopwatch = Stopwatch()..start();
    await service.batchVerify(
      files,
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    stopwatch.stop();
    print('Baseline batchVerify took: ${stopwatch.elapsedMilliseconds} ms');

    await dir.delete(recursive: true);
  });
}

import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('HardwareInfo', () {
    test('detect() returns sane values for the running host', () {
      final info = HardwareInfo.detect();
      expect(info.processorCount, greaterThanOrEqualTo(1));
      expect(info.operatingSystem, Platform.operatingSystem);
      expect(info.hostname, Platform.localHostname);
      expect(info.dartVersion, isNotEmpty);
    });

    test('recommendedBatchConcurrency leaves a core free on >1 core hosts', () {
      const info = HardwareInfo(
        processorCount: 4,
        operatingSystem: 'linux',
        operatingSystemVersion: '0',
        hostname: 'h',
        architecture: 'x64',
        dartVersion: 'test',
        localHostname: 'h',
      );
      expect(info.recommendedBatchConcurrency(), 3);
    });

    test('recommendedBatchConcurrency returns 1 on single-core hosts', () {
      const info = HardwareInfo(
        processorCount: 1,
        operatingSystem: 'linux',
        operatingSystemVersion: '0',
        hostname: 'h',
        architecture: 'x64',
        dartVersion: 'test',
        localHostname: 'h',
      );
      expect(info.recommendedBatchConcurrency(), 1);
    });

    test('recommendedBlockSizeBytes scales with core count', () {
      int blockFor(int cores) => HardwareInfo(
        processorCount: cores,
        operatingSystem: 'linux',
        operatingSystemVersion: '0',
        hostname: 'h',
        architecture: 'x64',
        dartVersion: 'test',
        localHostname: 'h',
      ).recommendedBlockSizeBytes();

      expect(blockFor(1), 32768);
      expect(blockFor(2), 65536);
      expect(blockFor(4), 131072);
      expect(blockFor(8), 262144);
    });

    test('toJson contains the expected keys', () {
      final json = HardwareInfo.detect().toJson();
      expect(
        json.keys,
        containsAll([
          'processor_count',
          'operating_system',
          'hostname',
          'architecture',
          'dart_version',
          'recommended_batch_concurrency',
          'recommended_block_size_bytes',
        ]),
      );
    });
  });
}

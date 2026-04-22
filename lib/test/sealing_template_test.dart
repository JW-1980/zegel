import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('SealingTemplate', () {
    test('round trips through JSON', () {
      final template = SealingTemplate(
        name: 'quarterly-report',
        description: 'Sealing preset for quarterly reports',
        contentType: 'application/pdf',
        classification: 'CONFIDENTIAL',
        compress: true,
        passwordDerived: false,
        expirationFromNow: const Duration(days: 90),
        blockSize: 131072,
        publicMetadata: {'department': 'finance'},
        metadata: {'classification_note': 'internal only'},
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final copy = SealingTemplate.fromJson(template.toJson());
      expect(copy.name, template.name);
      expect(copy.description, template.description);
      expect(copy.contentType, template.contentType);
      expect(copy.classification, template.classification);
      expect(copy.compress, template.compress);
      expect(copy.passwordDerived, template.passwordDerived);
      expect(copy.expirationFromNow, template.expirationFromNow);
      expect(copy.blockSize, template.blockSize);
      expect(copy.publicMetadata, template.publicMetadata);
      expect(copy.metadata, template.metadata);
      expect(
        copy.createdAt.toIso8601String(),
        template.createdAt.toIso8601String(),
      );
    });

    test('copyWith overrides fields', () {
      final template = SealingTemplate(
        name: 'a',
        compress: false,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final copy = template.copyWith(compress: true, name: 'b');
      expect(copy.name, 'b');
      expect(copy.compress, isTrue);
      // original unchanged
      expect(template.name, 'a');
      expect(template.compress, isFalse);
    });
  });

  group('SealingTemplateStore', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('zegel_tmpl_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('save/load/list/delete work end to end', () {
      final store = SealingTemplateStore(tmp.path);
      expect(store.list(), isEmpty);

      store.save(
        SealingTemplate(name: 'alpha', createdAt: DateTime.utc(2026, 1, 1)),
      );
      store.save(
        SealingTemplate(name: 'beta', createdAt: DateTime.utc(2026, 1, 1)),
      );

      expect(store.list(), ['alpha', 'beta']);

      final loaded = store.load('alpha');
      expect(loaded, isNotNull);
      expect(loaded!.name, 'alpha');
      expect(store.load('missing'), isNull);

      expect(store.delete('alpha'), isTrue);
      expect(store.delete('alpha'), isFalse);
      expect(store.list(), ['beta']);
    });

    test('sanitizes filesystem-hostile characters in names', () {
      final store = SealingTemplateStore(tmp.path);
      store.save(
        SealingTemplate(
          name: 'crazy/name:1',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final names = store.list();
      expect(names, hasLength(1));
      expect(names.single, contains('crazy_name_1'));
    });
  });
}

import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('TemplateManager', () {
    late Directory tempDir;
    late SealingTemplateStore store;
    late TemplateManager manager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('template_manager_test_');
      store = SealingTemplateStore(tempDir.path);
      manager = TemplateManager(store);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------------
    SealingTemplate _template(String name, {String? description}) =>
        SealingTemplate(
          name: name,
          description: description,
          createdAt: DateTime.utc(2024, 1, 1),
        );

    // -----------------------------------------------------------------------
    // upsert / get
    // -----------------------------------------------------------------------
    group('upsert and get', () {
      test('get returns null when template does not exist', () {
        expect(manager.get('missing'), isNull);
      });

      test('get returns the template after upsert', () {
        manager.upsert(_template('alpha'));
        final t = manager.get('alpha');
        expect(t, isNotNull);
        expect(t!.name, 'alpha');
      });

      test('upsert overwrites an existing template with the same name', () {
        manager.upsert(_template('replace-me', description: 'v1'));
        manager.upsert(_template('replace-me', description: 'v2'));
        expect(manager.get('replace-me')!.description, 'v2');
      });

      test('multiple distinct templates can be stored', () {
        manager.upsert(_template('a'));
        manager.upsert(_template('b'));
        manager.upsert(_template('c'));
        expect(manager.list().toSet(), containsAll(['a', 'b', 'c']));
      });
    });

    // -----------------------------------------------------------------------
    // list / allTemplates
    // -----------------------------------------------------------------------
    group('list', () {
      test('returns empty list when no templates exist', () {
        expect(manager.list(), isEmpty);
      });

      test('returns names of all stored templates', () {
        manager.upsert(_template('first'));
        manager.upsert(_template('second'));
        expect(manager.list(), containsAll(['first', 'second']));
      });
    });

    group('allTemplates', () {
      test('returns SealingTemplate objects for each name', () {
        manager.upsert(_template('x'));
        manager.upsert(_template('y'));
        final all = manager.allTemplates();
        expect(all.length, 2);
        final names = all.map((t) => t.name).toSet();
        expect(names, containsAll(['x', 'y']));
      });

      test('returns empty list when store is empty', () {
        expect(manager.allTemplates(), isEmpty);
      });
    });

    // -----------------------------------------------------------------------
    // update
    // -----------------------------------------------------------------------
    group('update', () {
      test('updates description of an existing template', () {
        manager.upsert(_template('upd', description: 'old'));
        final updated = manager.update('upd', description: 'new');
        expect(updated.description, 'new');
        expect(manager.get('upd')!.description, 'new');
      });

      test('updates contentType', () {
        manager.upsert(_template('ct'));
        final updated = manager.update('ct', contentType: 'application/pdf');
        expect(updated.contentType, 'application/pdf');
      });

      test('updates compress flag', () {
        manager.upsert(_template('comp'));
        final updated = manager.update('comp', compress: true);
        expect(updated.compress, isTrue);
      });

      test('updates classification', () {
        manager.upsert(_template('cls'));
        final updated = manager.update('cls', classification: 'TOP_SECRET');
        expect(updated.classification, 'TOP_SECRET');
      });

      test('updates blockSize', () {
        manager.upsert(_template('bs'));
        final updated = manager.update('bs', blockSize: 65536);
        expect(updated.blockSize, 65536);
      });

      test('updates expirationFromNow', () {
        manager.upsert(_template('exp'));
        final updated = manager.update(
          'exp',
          expirationFromNow: const Duration(days: 30),
        );
        expect(updated.expirationFromNow, const Duration(days: 30));
      });

      test('throws StateError when template does not exist', () {
        expect(
          () => manager.update('ghost', description: 'x'),
          throwsA(isA<StateError>()),
        );
      });

      test('name is preserved after update', () {
        manager.upsert(_template('stable-name'));
        final updated = manager.update('stable-name', description: 'changed');
        expect(updated.name, 'stable-name');
      });
    });

    // -----------------------------------------------------------------------
    // delete
    // -----------------------------------------------------------------------
    group('delete', () {
      test('returns true when the template existed', () {
        manager.upsert(_template('to-del'));
        expect(manager.delete('to-del'), isTrue);
      });

      test('returns false when the template did not exist', () {
        expect(manager.delete('phantom'), isFalse);
      });

      test('deleted template is no longer returned by get', () {
        manager.upsert(_template('gone'));
        manager.delete('gone');
        expect(manager.get('gone'), isNull);
      });

      test('deleted template is no longer in list', () {
        manager.upsert(_template('rem'));
        manager.upsert(_template('keep'));
        manager.delete('rem');
        expect(manager.list(), isNot(contains('rem')));
        expect(manager.list(), contains('keep'));
      });

      test('deleting the default template clears the default', () {
        manager.upsert(_template('def'));
        manager.setDefault('def');
        manager.delete('def');
        expect(manager.defaultTemplate(), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // duplicate
    // -----------------------------------------------------------------------
    group('duplicate', () {
      test('creates a new template under the new name', () {
        manager.upsert(
          _template('original', description: 'desc'),
        );
        final copy = manager.duplicate('original', 'copy');
        expect(copy, isNotNull);
        expect(copy!.name, 'copy');
        expect(manager.get('copy'), isNotNull);
      });

      test('copy preserves description from source', () {
        manager.upsert(_template('src', description: 'inherited'));
        final copy = manager.duplicate('src', 'dst');
        expect(copy!.description, 'inherited');
      });

      test('source template still exists after duplicate', () {
        manager.upsert(_template('orig'));
        manager.duplicate('orig', 'dup');
        expect(manager.get('orig'), isNotNull);
      });

      test('returns null when source does not exist', () {
        final result = manager.duplicate('nonexistent', 'new-name');
        expect(result, isNull);
      });

      test('duplicate with a different name does not overwrite source', () {
        manager.upsert(_template('base'));
        manager.duplicate('base', 'branch');
        expect(manager.get('base'), isNotNull);
        expect(manager.get('branch'), isNotNull);
        expect(manager.list().length, 2);
      });
    });

    // -----------------------------------------------------------------------
    // setDefault / defaultTemplate
    // -----------------------------------------------------------------------
    group('setDefault and defaultTemplate', () {
      test('defaultTemplate returns null when none is set', () {
        expect(manager.defaultTemplate(), isNull);
      });

      test('setDefault marks a template as the default', () {
        manager.upsert(_template('preferred'));
        manager.setDefault('preferred');
        expect(manager.defaultTemplate()!.name, 'preferred');
      });

      test('setDefault can be changed to a different template', () {
        manager.upsert(_template('a'));
        manager.upsert(_template('b'));
        manager.setDefault('a');
        manager.setDefault('b');
        expect(manager.defaultTemplate()!.name, 'b');
      });

      test('setDefault throws StateError for an unknown template', () {
        expect(
          () => manager.setDefault('missing'),
          throwsA(isA<StateError>()),
        );
      });

      test('defaultTemplate returns null after the default is deleted', () {
        manager.upsert(_template('def'));
        manager.setDefault('def');
        manager.delete('def');
        expect(manager.defaultTemplate(), isNull);
      });

      test(
          'setDefault references the live store — changes reflected immediately',
          () {
        manager.upsert(_template('live', description: 'v1'));
        manager.setDefault('live');
        // Update the template after setting default.
        manager.update('live', description: 'v2');
        expect(manager.defaultTemplate()!.description, 'v2');
      });
    });
  });
}

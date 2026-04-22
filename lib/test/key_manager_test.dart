import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('KeyManager', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('key_manager_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // Generates a fresh 32-byte key (non-secret test data).
    Uint8List makeKey([int seed = 0xAB]) =>
        Uint8List.fromList(List<int>.filled(32, seed));

    String dbPath() => '${tempDir.path}/keys.json';

    // -----------------------------------------------------------------------
    // Factory constructors
    // -----------------------------------------------------------------------
    group('KeyManager.empty', () {
      test('starts with no entries', () {
        final km = KeyManager.empty();
        expect(km.list(), isEmpty);
      });
    });

    group('KeyManager.load', () {
      test('returns empty manager when file does not exist', () {
        final km = KeyManager.load('${tempDir.path}/nonexistent.json');
        expect(km.list(), isEmpty);
      });

      test('round-trips through save and load', () {
        final km = KeyManager.empty();
        km.create(name: 'test-key', keyBytes: makeKey(0x01));
        km.save(dbPath());

        final loaded = KeyManager.load(dbPath());
        expect(loaded.list().length, 1);
        expect(loaded.list().first.name, 'test-key');
      });

      test('loads all entries from disk', () {
        final km = KeyManager.empty();
        km.create(name: 'alpha', keyBytes: makeKey(0x01));
        km.create(name: 'beta', keyBytes: makeKey(0x02));
        km.save(dbPath());

        final loaded = KeyManager.load(dbPath());
        final names = loaded.list().map((e) => e.name).toSet();
        expect(names, containsAll(['alpha', 'beta']));
      });
    });

    // -----------------------------------------------------------------------
    // create
    // -----------------------------------------------------------------------
    group('create', () {
      test('returns a KeyEntry with the given name', () {
        final km = KeyManager.empty();
        final entry = km.create(name: 'my-key', keyBytes: makeKey());
        expect(entry.name, 'my-key');
      });

      test('assigns a non-empty id', () {
        final km = KeyManager.empty();
        final entry = km.create(name: 'id-test', keyBytes: makeKey());
        expect(entry.id, isNotEmpty);
      });

      test('stores a SHA-256 fingerprint (64 hex chars)', () {
        final km = KeyManager.empty();
        final entry = km.create(name: 'fp-test', keyBytes: makeKey());
        expect(entry.fingerprint.length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.fingerprint), isTrue);
      });

      test('wipes the keyBytes buffer to zeros after creating', () {
        final km = KeyManager.empty();
        final key = makeKey(0xFF);
        km.create(name: 'wipe-test', keyBytes: key);
        // After create the buffer should be zeroed.
        expect(key.every((b) => b == 0), isTrue);
      });

      test('throws ArgumentError when keyBytes is not 32 bytes', () {
        final km = KeyManager.empty();
        expect(
          () => km.create(
            name: 'bad-len',
            keyBytes: Uint8List.fromList([1, 2, 3]),
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts optional description', () {
        final km = KeyManager.empty();
        final entry = km.create(
          name: 'described',
          keyBytes: makeKey(),
          description: 'A test key',
        );
        expect(entry.description, 'A test key');
      });

      test('accepts optional expiresAt', () {
        final km = KeyManager.empty();
        final expiry = DateTime.utc(2030, 1, 1);
        final entry = km.create(
          name: 'expiring',
          keyBytes: makeKey(),
          expiresAt: expiry,
        );
        expect(entry.expiresAt, expiry);
      });

      test('two distinct keys produce different fingerprints', () {
        final km = KeyManager.empty();
        final e1 = km.create(name: 'k1', keyBytes: makeKey(0x01));
        final e2 = km.create(name: 'k2', keyBytes: makeKey(0x02));
        expect(e1.fingerprint, isNot(e2.fingerprint));
      });

      test('each created entry gets a unique id', () {
        final km = KeyManager.empty();
        final ids = <String>{};
        for (var i = 0; i < 5; i++) {
          final e = km.create(name: 'k$i', keyBytes: makeKey(i));
          ids.add(e.id);
        }
        expect(ids.length, 5);
      });
    });

    // -----------------------------------------------------------------------
    // read
    // -----------------------------------------------------------------------
    group('read', () {
      test('returns the entry with the given id', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'readable', keyBytes: makeKey());
        expect(km.read(e.id), isNotNull);
        expect(km.read(e.id)!.name, 'readable');
      });

      test('returns null for an unknown id', () {
        final km = KeyManager.empty();
        expect(km.read('nonexistent'), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // findByFingerprint
    // -----------------------------------------------------------------------
    group('findByFingerprint', () {
      test('finds an entry by its fingerprint', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'findme', keyBytes: makeKey(0xCC));
        final found = km.findByFingerprint(e.fingerprint);
        expect(found, isNotNull);
        expect(found!.id, e.id);
      });

      test('returns null when fingerprint is not in the registry', () {
        final km = KeyManager.empty();
        expect(km.findByFingerprint('a' * 64), isNull);
      });
    });

    // -----------------------------------------------------------------------
    // update
    // -----------------------------------------------------------------------
    group('update', () {
      test('updates the name field', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'old-name', keyBytes: makeKey());
        final updated = km.update(e.id, name: 'new-name');
        expect(updated, isNotNull);
        expect(updated!.name, 'new-name');
      });

      test('updates the description field', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'k', keyBytes: makeKey(), description: 'old');
        final updated = km.update(e.id, description: 'new description');
        expect(updated!.description, 'new description');
      });

      test('updates expiresAt', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'exp', keyBytes: makeKey());
        final newExpiry = DateTime.utc(2035, 6, 15);
        final updated = km.update(e.id, expiresAt: newExpiry);
        expect(updated!.expiresAt, newExpiry);
      });

      test('preserves fingerprint after update', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'fp-stable', keyBytes: makeKey(0xAA));
        final updated = km.update(e.id, name: 'renamed');
        expect(updated!.fingerprint, e.fingerprint);
      });

      test('returns null for an unknown id', () {
        final km = KeyManager.empty();
        expect(km.update('ghost', name: 'x'), isNull);
      });

      test('read returns updated data after update', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'before', keyBytes: makeKey());
        km.update(e.id, name: 'after');
        expect(km.read(e.id)!.name, 'after');
      });
    });

    // -----------------------------------------------------------------------
    // delete
    // -----------------------------------------------------------------------
    group('delete', () {
      test('returns true when the entry existed', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'to-delete', keyBytes: makeKey());
        expect(km.delete(e.id), isTrue);
      });

      test('returns false when the entry did not exist', () {
        final km = KeyManager.empty();
        expect(km.delete('nonexistent'), isFalse);
      });

      test('entry is no longer accessible after delete', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'gone', keyBytes: makeKey());
        km.delete(e.id);
        expect(km.read(e.id), isNull);
      });

      test('list does not include deleted entry', () {
        final km = KeyManager.empty();
        final e = km.create(name: 'del-list', keyBytes: makeKey());
        km.create(name: 'survivor', keyBytes: makeKey(0x02));
        km.delete(e.id);
        expect(km.list().map((x) => x.name), isNot(contains('del-list')));
        expect(km.list().map((x) => x.name), contains('survivor'));
      });
    });

    // -----------------------------------------------------------------------
    // list
    // -----------------------------------------------------------------------
    group('list', () {
      test('returns all entries when includeExpired = true (default)', () {
        final km = KeyManager.empty();
        km.create(name: 'active', keyBytes: makeKey(0x01));
        km.create(
          name: 'expired',
          keyBytes: makeKey(0x02),
          expiresAt: DateTime.utc(2000, 1, 1),
        );
        expect(km.list(includeExpired: true).length, 2);
      });

      test('excludes expired entries when includeExpired = false', () {
        final km = KeyManager.empty();
        km.create(name: 'active', keyBytes: makeKey(0x01));
        km.create(
          name: 'expired',
          keyBytes: makeKey(0x02),
          expiresAt: DateTime.utc(2000, 1, 1),
        );
        final live = km.list(includeExpired: false);
        expect(live.length, 1);
        expect(live.first.name, 'active');
      });

      test(
        'entry with future expiry is included when includeExpired = false',
        () {
          final km = KeyManager.empty();
          km.create(
            name: 'future',
            keyBytes: makeKey(),
            expiresAt: DateTime.utc(2099, 1, 1),
          );
          expect(km.list(includeExpired: false).length, 1);
        },
      );

      test('entries are sorted by createdAt ascending', () {
        final km = KeyManager.empty();
        // Create entries with explicit timestamps so order is deterministic.
        final t1 = DateTime.utc(2024, 1, 1);
        final t2 = DateTime.utc(2024, 6, 1);
        final t3 = DateTime.utc(2025, 1, 1);
        km.create(name: 'c', keyBytes: makeKey(0x03), createdAt: t3);
        km.create(name: 'a', keyBytes: makeKey(0x01), createdAt: t1);
        km.create(name: 'b', keyBytes: makeKey(0x02), createdAt: t2);

        final names = km.list().map((e) => e.name).toList();
        expect(names, ['a', 'b', 'c']);
      });

      test('returns empty list when no entries exist', () {
        final km = KeyManager.empty();
        expect(km.list(), isEmpty);
      });

      test('includeExpired uses custom now for cutoff', () {
        final km = KeyManager.empty();
        final expiry = DateTime.utc(2024, 6, 1);
        km.create(name: 'borderline', keyBytes: makeKey(), expiresAt: expiry);
        // Querying with a "now" before the expiry should include the entry.
        final before = km.list(
          includeExpired: false,
          now: DateTime.utc(2024, 1, 1),
        );
        expect(before.length, 1);

        // Querying with "now" after expiry should exclude it.
        final after = km.list(
          includeExpired: false,
          now: DateTime.utc(2025, 1, 1),
        );
        expect(after.isEmpty, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // encode / save
    // -----------------------------------------------------------------------
    group('encode and save', () {
      test('encode returns valid JSON string', () {
        final km = KeyManager.empty();
        km.create(name: 'enc-test', keyBytes: makeKey());
        final json = km.encode();
        expect(json, contains('"keys"'));
        expect(json, contains('enc-test'));
      });

      test('saved file is readable as text', () {
        final km = KeyManager.empty();
        km.create(name: 'save-test', keyBytes: makeKey());
        km.save(dbPath());
        final content = File(dbPath()).readAsStringSync();
        expect(content, isNotEmpty);
        expect(content, contains('save-test'));
      });
    });
  });
}

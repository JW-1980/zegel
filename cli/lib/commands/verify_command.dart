import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Verifies the integrity of a .zgl file.
///
/// Usage:
///   zegel verify &lt;file.zgl&gt; -k &lt;key-hex&gt;
///
/// Exit codes:
///   0 = valid (intact)
///   1 = tampered (integrity check failed)
///   2 = expired (cryptographic expiration reached)
class VerifyCommand extends Command<int> {
  @override
  final String name = 'verify';

  @override
  String get description =>
      'Verify the integrity and authenticity of a .zgl file.\n'
      '\n'
      'Performs a complete integrity check: validates the master seal,\n'
      'Merkle tree, all block HMACs, and key commitment. If any byte\n'
      'has been modified, the file is reported as TAMPERED.\n'
      '\n'
      'Use --verbose to see detailed block-by-block verification results,\n'
      'attestation details, and audit trail entries.\n'
      '\n'
      'Use --check-attestation-policy to require that specific roles have\n'
      'attested to the file (e.g., require both a reviewer and a notary).\n'
      '\n'
      'Exit codes:\n'
      '  0  VALID - file integrity verified\n'
      '  1  TAMPERED - integrity check failed / format error\n'
      '  2  EXPIRED - cryptographic expiration reached\n'
      '  3  POLICY_VIOLATION - attestation policy not met\n'
      '\n'
      'Examples:\n'
      '  zegel verify document.zgl -k \$(cat master.key)\n'
      '  zegel verify document.zgl --key-file master.key --verbose\n'
      '  zegel verify document.zgl -k <hex> --quiet\n'
      '  zegel verify contract.zgl -k <hex> --check-attestation-policy reviewer,notary';

  @override
  final String invocation = 'zegel verify <file.zgl> [options]';

  VerifyCommand() {
    addKeyOptions(argParser);

    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help:
          'Show detailed verification information including block\n'
          'directory, per-block hashes, attestation HMACs, and\n'
          'audit trail entries.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'quiet',
      abbr: 'q',
      help:
          'Only output the result (VALID, TAMPERED, or EXPIRED).\n'
          'Useful for scripting.',
      defaultsTo: false,
    );

    argParser.addOption(
      'check-attestation-policy',
      help:
          'Comma-separated list of required attestation roles.\n'
          'Verification fails (exit code 3) if any role is missing.\n'
          'Valid roles: owner, signer, witness, notary, auditor, reviewer.',
      valueHelp: 'role1,role2',
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('No .zgl file specified.', usage);
    }

    final filePath = argResults!.rest.first;
    final file = File(filePath);

    if (!file.existsSync()) {
      exitError('File not found: $filePath');
    }

    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final fileBytes = await file.readAsBytes();
    final verbose = argResults!['verbose'] as bool;
    final quiet = argResults!['quiet'] as bool;

    // Create reader and verify.
    const reader = ZegelReader();

    try {
      final result = reader.verify(fileBytes, masterKey);

      // Check attestation policy if specified.
      final policyStr = argResults!['check-attestation-policy'] as String?;
      if (policyStr != null && policyStr.isNotEmpty) {
        final requiredRoles = policyStr
            .split(',')
            .map((r) => r.trim().toLowerCase())
            .where((r) => r.isNotEmpty)
            .toList();

        // Validate role names.
        for (final role in requiredRoles) {
          if (!attestationRoles.contains(role)) {
            exitError(
              'Invalid attestation role in policy: "$role". '
              'Valid roles: ${attestationRoles.join(', ')}.',
            );
          }
        }

        // Check that each required role has at least one attestation.
        final attestedRoles = <String>{};
        if (result.attestations != null) {
          for (final att in result.attestations!) {
            final role = att['role'] as String?;
            if (role != null) {
              attestedRoles.add(role.toLowerCase());
            }
          }
        }

        final missingRoles = requiredRoles
            .where((r) => !attestedRoles.contains(r))
            .toList();
        if (missingRoles.isNotEmpty) {
          if (quiet) {
            stdout.writeln('POLICY_VIOLATION');
          } else {
            stdout.writeln(
              '${Ansi.error('POLICY_VIOLATION')} - Required attestation '
              'roles are missing.',
            );
            stdout.writeln();
            stderr.writeln('  Missing roles: ${missingRoles.join(', ')}');
            stderr.writeln(
              '  Present roles: ${attestedRoles.isEmpty ? '(none)' : attestedRoles.join(', ')}',
            );
          }
          return 3;
        }
      }

      if (quiet) {
        stdout.writeln('VALID');
      } else {
        stdout.writeln('${Ansi.success('VALID')} - File integrity verified.');
        stdout.writeln();
        _printFileInfo(reader, result, fileBytes, filePath, verbose);
      }
      SecureMemory.wipe(masterKey);
      return 0;
    } on ZegelTamperedException catch (e) {
      if (quiet) {
        stdout.writeln('TAMPERED');
      } else {
        stdout.writeln(
          '${Ansi.error('TAMPERED')} - File integrity check FAILED.',
        );
        stdout.writeln();
        stderr.writeln('  Reason: ${e.message}');
      }
      SecureMemory.wipe(masterKey);
      SecureMemory.wipe(masterKey);
      return 1;
    } on ZegelExpiredException catch (e) {
      if (quiet) {
        stdout.writeln('EXPIRED');
      } else {
        stdout.writeln(
          '${Ansi.error('EXPIRED')} - File has passed its cryptographic '
          'expiration date.',
        );
        stdout.writeln();
        stderr.writeln('  Detail: ${e.message}');

        try {
          final inspection = reader.inspect(fileBytes);
          if (inspection.expirationTimestamp != null) {
            final expiresAt = DateTime.fromMillisecondsSinceEpoch(
              inspection.expirationTimestamp! * 1000,
              isUtc: true,
            );
            stdout.writeln('  Expired: ${formatTimestamp(expiresAt)}');
          }
        } catch (_) {
          // Could not inspect header for expiration details.
        }
      }
      return 2;
    } on ZegelFormatException catch (e) {
      if (quiet) {
        stdout.writeln('TAMPERED');
      } else {
        stderr.writeln('${Ansi.error('ERROR')} - Invalid file format.');
        stderr.writeln('  Reason: ${e.message}');
      }
      SecureMemory.wipe(masterKey);
      return 1;
    }
  }

  /// Prints file information after successful verification.
  void _printFileInfo(
    ZegelReader reader,
    ZegelResult result,
    Uint8List fileBytes,
    String filePath,
    bool verbose,
  ) {
    final inspection = reader.inspect(fileBytes);

    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      inspection.timestamp * 1000,
      isUtc: true,
    );

    stdout.writeln('  File:       $filePath');
    stdout.writeln('  Version:    ${inspection.version}');
    stdout.writeln('  Created:    ${formatTimestamp(createdAt)}');
    if (inspection.filename != null) {
      stdout.writeln('  Filename:   ${inspection.filename}');
    }
    if (inspection.contentType != null) {
      stdout.writeln('  Type:       ${inspection.contentType}');
    }
    stdout.writeln('  Blocks:     ${inspection.blockCount}');

    if (inspection.expirationTimestamp != null) {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        inspection.expirationTimestamp! * 1000,
        isUtc: true,
      );
      stdout.writeln('  Expires:    ${formatTimestamp(expiresAt)}');
    }

    // Show flags.
    final flags = decodeFlagNames(inspection.flags);
    if (flags.isNotEmpty) {
      stdout.writeln('  Flags:      ${flags.join(', ')}');
    }

    // Show encrypted metadata if present.
    if (result.metadata != null && result.metadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Metadata:'));
      for (final entry in result.metadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    // Show public metadata if present.
    if (inspection.publicMetadata != null &&
        inspection.publicMetadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Public Metadata:'));
      for (final entry in inspection.publicMetadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    // Show redacted blocks.
    if (result.redactedBlocks != null && result.redactedBlocks!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(
        Ansi.warning('  Redacted blocks: ${result.redactedBlocks!.join(', ')}'),
      );
    }

    // Show attestations if present.
    if (result.attestations != null && result.attestations!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Attestations:'));
      for (final att in result.attestations!) {
        stdout.writeln('    Signer: ${att['signer_id']}');
        stdout.writeln('      Statement: ${att['statement']}');
        if (att['timestamp'] != null) {
          final ts = DateTime.fromMillisecondsSinceEpoch(
            (att['timestamp'] as int) * 1000,
            isUtc: true,
          );
          stdout.writeln('      Time:      ${formatTimestamp(ts)}');
        }
      }
    }

    // Show audit trail if present.
    if (result.auditTrail != null && result.auditTrail!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Audit Trail:'));
      for (var i = 0; i < result.auditTrail!.length; i++) {
        final entry = result.auditTrail![i];
        final ts = entry['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (entry['timestamp'] as int) * 1000,
                isUtc: true,
              )
            : null;
        stdout.writeln(
          '    ${i + 1}. [${entry['action']}] by ${entry['actor']} '
          '${ts != null ? formatTimestamp(ts) : 'unknown time'}',
        );
      }
    }

    if (verbose) {
      // Use raw binary parsing to show block directory details.
      try {
        final rawHeader = RawZegelHeader.parse(fileBytes);
        stdout.writeln();
        stdout.writeln(Ansi.header('  Block Directory:'));
        for (var i = 0; i < rawHeader.blockCount; i++) {
          final block = rawHeader.blockDirectory[i];
          stdout.writeln(
            '    [$i] ${blockTypeName(block.type)} '
            '${formatFileSize(block.ciphertextLength)} '
            'hash=${hexEncode(Uint8List.fromList(block.plaintextHash.take(8).toList()))}...',
          );
        }
      } catch (_) {
        // Could not parse block directory.
      }
    }
  }
}

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:zegel_cli/commands/attest_command.dart';
import 'package:zegel_cli/commands/audit_command.dart';
import 'package:zegel_cli/commands/batch_command.dart';
import 'package:zegel_cli/commands/canary_command.dart';
import 'package:zegel_cli/commands/classify_command.dart';
import 'package:zegel_cli/commands/disclose_command.dart';
import 'package:zegel_cli/commands/excerpt_command.dart';
import 'package:zegel_cli/commands/extract_command.dart';
import 'package:zegel_cli/commands/hierarchical_split_key_command.dart';
import 'package:zegel_cli/commands/identity_command.dart';
import 'package:zegel_cli/commands/inspect_command.dart';
import 'package:zegel_cli/commands/keygen_command.dart';
import 'package:zegel_cli/commands/manifest_command.dart';
import 'package:zegel_cli/commands/media_metadata_command.dart';
import 'package:zegel_cli/commands/provenance_command.dart';
import 'package:zegel_cli/commands/redact_command.dart';
import 'package:zegel_cli/commands/seal_command.dart';
import 'package:zegel_cli/commands/split_key_command.dart';
import 'package:zegel_cli/commands/supply_chain_command.dart';
import 'package:zegel_cli/commands/timestamp_command.dart';
import 'package:zegel_cli/commands/verify_command.dart';
import 'package:zegel_cli/commands/version_chain_command.dart';

/// Application version.
const String version = '1.4.0';

/// Zegel CLI - tamper-proof container format tool.
///
/// Provides commands for sealing, verifying, extracting, and managing
/// files in the Zegel (.zgl) format.
void main(List<String> arguments) async {
  // Handle --version flag before CommandRunner takes over.
  if (arguments.length == 1 && arguments[0] == '--version') {
    stdout.writeln('zegel $version');
    exit(0);
  }

  final runner = CommandRunner<int>(
    'zegel',
    'Zegel CLI - Tamper-proof container format tool (v$version)\n'
        '\n'
        'Seal any file so that modifying a single byte makes the entire\n'
        'content physically unreadable. Uses AES-256-GCM encryption with\n'
        'Merkle tree integrity binding.\n'
        '\n'
        'Usage: zegel <command> [arguments] [options]\n'
        '\n'
        'Core commands:\n'
        '  seal                  Seal a file into a tamper-proof .zgl container\n'
        '  verify                Verify the integrity of a .zgl file\n'
        '  extract               Extract original content from a verified .zgl file\n'
        '  inspect               Inspect a .zgl file header (no key required)\n'
        '  keygen                Generate a cryptographically secure master key\n'
        '\n'
        'Security commands:\n'
        '  redact                Permanently redact specific blocks from a .zgl file\n'
        '  split-key             Split a master key into M-of-N Shamir shares\n'
        '  reconstruct           Reconstruct a master key from Shamir shares\n'
        '  attest                Add a co-signature attestation to a .zgl file\n'
        '\n'
        'Disclosure commands:\n'
        '  disclose              Generate a selective disclosure token for specific blocks\n'
        '  extract-with-token    Extract content using a disclosure token (no master key)\n'
        '  excerpt-proof         Generate a Merkle proof for a specific block\n'
        '  verify-excerpt        Verify an excerpt proof against a .zgl file\n'
        '\n'
        'Batch commands:\n'
        '  batch-verify          Verify multiple .zgl files at once\n'
        '  batch-seal            Seal multiple files from a directory\n'
        '  manifest-create       Create a manifest from .zgl files\n'
        '  manifest-verify       Verify a manifest against files on disk\n'
        '\n'
        'Classification commands:\n'
        '  classify              Set classification level on a .zgl file\n'
        '  declassify            Reduce classification level of a .zgl file\n'
        '\n'
        'Versioning commands:\n'
        '  version-chain-verify  Verify a sequence of .zgl files are linked\n'
        '  provenance-verify     Verify provenance chain in a .zgl file\n'
        '\n'
        'Audit & Forensics commands:\n'
        '  audit                 Audit trail operations (view, add, verify-chain)\n'
        '  canary                Canary trap fingerprinting (embed, identify)\n'
        '  timestamp             Trusted timestamp operations (create, verify)\n'
        '\n'
        'Identity & Signing commands:\n'
        '  sign                  Sign a .zgl file with an Ed25519 key\n'
        '  verify-signature      Verify an Ed25519 signature on a .zgl file\n'
        '  identity-keygen       Generate an Ed25519 signing keypair\n'
        '\n'
        'Supply Chain commands:\n'
        '  verify-binary         Verify the integrity of a Zegel binary\n'
        '  build-attest          Create a build provenance attestation\n'
        '  verify-build          Verify a build attestation\n'
        '  audit-entropy         Audit randomness quality in a .zgl file\n'
        '\n'
        'Advanced commands:\n'
        '  hierarchical-split    Hierarchical key splitting (split, reconstruct)\n'
        '  media-metadata        Media metadata operations (extract, view)\n'
        '\n'
        'Global flags:\n'
        '  --help                Show help for a command\n'
        '  --version             Show the Zegel CLI version\n'
        '\n'
        'Examples:\n'
        '  # Generate a key and seal a file\n'
        '  zegel keygen -o master.key\n'
        '  zegel seal document.pdf --key-file master.key -o document.pdf.zgl\n'
        '\n'
        '  # Verify and extract\n'
        '  zegel verify document.pdf.zgl --key-file master.key\n'
        '  zegel extract document.pdf.zgl --key-file master.key -o recovered.pdf\n'
        '\n'
        '  # Split a key for shared custody\n'
        '  zegel split-key --key-file master.key --threshold 3 --shares 5 -o shares/\n'
        '  zegel reconstruct shares/share_1.key shares/share_2.key shares/share_3.key -o recovered.key\n'
        '\n'
        '  # Selective disclosure (share specific blocks without the master key)\n'
        '  zegel disclose report.zgl -k <hex> --blocks 0,2 -o token.json\n'
        '  zegel extract-with-token report.zgl --token token.json -o partial.pdf\n'
        '\n'
        'Run "zegel <command> --help" for detailed usage of each command.',
  );

  // Core commands.
  runner.addCommand(SealCommand());
  runner.addCommand(VerifyCommand());
  runner.addCommand(ExtractCommand());
  runner.addCommand(InspectCommand());
  runner.addCommand(KeygenCommand());

  // Security commands.
  runner.addCommand(RedactCommand());
  runner.addCommand(SplitKeyCommand());
  runner.addCommand(ReconstructCommand());
  runner.addCommand(AttestCommand());

  // Disclosure commands.
  runner.addCommand(DiscloseCommand());
  runner.addCommand(ExtractWithTokenCommand());
  runner.addCommand(ExcerptProofCommand());
  runner.addCommand(VerifyExcerptCommand());

  // Batch commands.
  runner.addCommand(BatchVerifyCommand());
  runner.addCommand(BatchSealCommand());
  runner.addCommand(ManifestCreateCommand());
  runner.addCommand(ManifestVerifyCommand());

  // Classification commands.
  runner.addCommand(ClassifyCommand());
  runner.addCommand(DeclassifyCommand());

  // Versioning commands.
  runner.addCommand(VersionChainVerifyCommand());
  runner.addCommand(ProvenanceVerifyCommand());

  // Audit & Forensics commands.
  runner.addCommand(AuditCommand());
  runner.addCommand(CanaryCommand());
  runner.addCommand(TimestampCommand());

  // Identity & Signing commands.
  runner.addCommand(SignCommand());
  runner.addCommand(VerifySignatureCommand());
  runner.addCommand(IdentityKeygenCommand());

  // Supply Chain commands.
  runner.addCommand(VerifyBinaryCommand());
  runner.addCommand(BuildAttestCommand());
  runner.addCommand(VerifyBuildCommand());
  runner.addCommand(AuditEntropyCommand());

  // Advanced commands.
  runner.addCommand(HierarchicalSplitCommand());
  runner.addCommand(MediaMetadataCommand());

  try {
    final exitCode = await runner.run(arguments) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln(e.usage);
    exit(64); // EX_USAGE from sysexits.h
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1);
  } on FileSystemException catch (e) {
    stderr.writeln('Error: ${e.message}');
    if (e.path != null) {
      stderr.writeln('  Path: ${e.path}');
    }
    exit(1);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}

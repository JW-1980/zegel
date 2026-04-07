import os
import re

def process_cli_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # unused imports
    content = content.replace("import 'dart:typed_data';\n", "")
    if 'import \'package:crypto/crypto.dart\';' in content:
        content = content.replace("import 'package:crypto/crypto.dart';\n", "")

    # unused variables and unnecessary ! assertions
    if 'batch_command.dart' in filepath:
        content = content.replace("final verbose = parsed['verbose'] as bool;", "")
    if 'canary_command.dart' in filepath:
        content = content.replace("final result = reader.verify(bytes, key);", "")
    if 'disclose_command.dart' in filepath:
        content = content.replace("bytes!", "bytes")
    if 'excerpt_command.dart' in filepath:
        content = content.replace("final key = _hexToBytes(keyHex);", "")
    if 'keygen_command.dart' in filepath:
        content = content.replace("options.versionMinor!", "options.versionMinor")
    if 'redact_command.dart' in filepath:
        content = content.replace("bytes!", "bytes")
    if 'split_key_command.dart' in filepath:
        content = content.replace("options.versionMinor!", "options.versionMinor")

    with open(filepath, 'w') as f:
        f.write(content)

for root, dirs, files in os.walk('cli/lib/commands'):
    for file in files:
        if file.endswith('.dart'):
            process_cli_file(os.path.join(root, file))

print("Fixed cli issues.")

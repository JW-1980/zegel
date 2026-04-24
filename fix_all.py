import os
import subprocess

def run_cmd(cmd, cwd=None):
    print(f"Running: {cmd} in {cwd or '.'}")
    subprocess.run(cmd, shell=True, cwd=cwd)

# 1. Fix app imports
app_imports = {
    'app/lib/screens/attest_screen.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/screens/canary_screen.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/screens/disclose_screen.dart': ["import 'dart:io';", "import 'package:flutter/services.dart';"],
    'app/lib/screens/envelope_screen.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/screens/inspect_screen.dart': ["import 'dart:io';"],
    'app/lib/screens/keygen_screen.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/screens/provenance_screen.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/screens/split_key_screen.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/screens/timestamp_screen.dart': ["import 'dart:io';"],
    'app/lib/screens/version_chain_screen.dart': ["import 'dart:io';"],
    'app/lib/screens/wet_signature_screen.dart': ["import 'dart:io';", "import 'package:intl/intl.dart';"],
    'app/lib/services/contact_service.dart': ["import 'dart:io';"],
    'app/lib/services/file_service.dart': ["import 'dart:io';"],
    'app/lib/widgets/attestation_badge.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/widgets/audit_trail_view.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/widgets/command_palette.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/widgets/file_info_card.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/widgets/inactivity_lock.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/widgets/key_input.dart': ["import 'dart:io';", "import 'package:flutter/services.dart';"],
    'app/lib/widgets/party_manager.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/widgets/sensitive_field.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/widgets/zegel_data_table.dart': ["import 'package:flutter/services.dart';"],
}

for filepath, imports in app_imports.items():
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        continue
    with open(filepath, 'r') as f:
        content = f.read()
    for imp in imports:
        if imp not in content:
            content = f"{imp}\n{content}"
    with open(filepath, 'w') as f:
        f.write(content)

# 2. Fix typed_data unused import in media_metadata_screen.dart
media_meta = 'app/lib/screens/media_metadata_screen.dart'
if os.path.exists(media_meta):
    with open(media_meta, 'r') as f:
        lines = f.readlines()
    with open(media_meta, 'w') as f:
        for line in lines:
            if "import 'dart:typed_data';" not in line:
                f.write(line)

print("App fixes applied.")

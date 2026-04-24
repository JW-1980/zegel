import os

files_to_fix = {
    'app/lib/screens/canary_screen.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/screens/keygen_screen.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/screens/wet_signature_screen.dart': ["import 'dart:io';", "import 'package:intl/intl.dart';"],
    'app/lib/screens/envelope_screen.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/widgets/key_input.dart': ["import 'dart:io';", "import 'package:flutter/services.dart';"],
    'app/lib/widgets/file_info_card.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/widgets/attestation_badge.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/widgets/audit_trail_view.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/widgets/party_manager.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/screens/timestamp_screen.dart': ["import 'dart:io';"],
    'app/lib/screens/version_chain_screen.dart': ["import 'dart:io';"],
    'app/lib/screens/attest_screen.dart': ["import 'package:intl/intl.dart';"],
}

for filepath, imports in files_to_fix.items():
    if not os.path.exists(filepath):
        print(f"File {filepath} not found.")
        continue

    with open(filepath, 'r') as f:
        content = f.read()

    for imp in imports:
        if imp not in content:
            content = f"{imp}\n{content}"

    with open(filepath, 'w') as f:
        f.write(content)

print("Done fixing app imports.")

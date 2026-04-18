import os
import re

import_replacements = {
    "import 'dart:io';": [
        "app/lib/screens/timestamp_screen.dart",
        "app/lib/screens/version_chain_screen.dart",
        "app/lib/screens/wet_signature_screen.dart",
        "app/lib/services/contact_service.dart",
        "app/lib/services/file_service.dart",
        "app/lib/widgets/key_input.dart",
        "app/lib/screens/disclose_screen.dart",
        "app/lib/screens/inspect_screen.dart",
    ],
    "import 'package:intl/intl.dart';": [
        "app/lib/screens/wet_signature_screen.dart",
        "app/lib/widgets/attestation_badge.dart",
        "app/lib/widgets/audit_trail_view.dart",
        "app/lib/widgets/file_info_card.dart",
        "app/lib/screens/envelope_screen.dart",
        "app/lib/screens/attest_screen.dart",
        "app/lib/screens/provenance_screen.dart",
    ],
    "import 'package:flutter/services.dart';": [
        "app/lib/screens/canary_screen.dart",
        "app/lib/screens/keygen_screen.dart",
        "app/lib/widgets/command_palette.dart",
        "app/lib/widgets/key_input.dart",
        "app/lib/widgets/party_manager.dart",
        "app/lib/widgets/sensitive_field.dart",
        "app/lib/widgets/zegel_data_table.dart",
        "app/lib/widgets/inactivity_lock.dart",
        "app/lib/screens/disclose_screen.dart",
        "app/lib/screens/split_key_screen.dart",
    ]
}

for import_stmt, files in import_replacements.items():
    for filepath in files:
        if not os.path.exists(filepath):
            continue
        with open(filepath, 'r') as f:
            content = f.read()

        if import_stmt not in content:
            # find first import
            content = re.sub(r'^(import .*?;)', rf'{import_stmt}\n\1', content, count=1, flags=re.MULTILINE)

            with open(filepath, 'w') as f:
                f.write(content)

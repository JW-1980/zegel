import os

files_to_fix = {
    'app/lib/services/file_service.dart': ["import 'dart:io';"],
    'app/lib/screens/split_key_screen.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/screens/disclose_screen.dart': ["import 'dart:io';", "import 'package:flutter/services.dart';"],
    'app/lib/screens/provenance_screen.dart': ["import 'package:intl/intl.dart';"],
    'app/lib/screens/inspect_screen.dart': ["import 'dart:io';"],
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

print("Done fixing more app imports.")

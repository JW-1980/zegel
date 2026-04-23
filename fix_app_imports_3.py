import os

files_to_fix = {
    'app/lib/services/contact_service.dart': ["import 'dart:io';"],
    'app/lib/widgets/command_palette.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/widgets/inactivity_lock.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/widgets/sensitive_field.dart': ["import 'package:flutter/services.dart';"],
    'app/lib/widgets/zegel_data_table.dart': ["import 'package:flutter/services.dart';"],
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

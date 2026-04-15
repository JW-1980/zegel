import os
import glob
import re

def fix_with_opacity(content):
    return content.replace('.withOpacity(', '.withValues(alpha: ')

def fix_imports(content):
    content = re.sub(r"import 'dart:io';\n", "", content)
    content = re.sub(r"import 'dart:typed_data';\n", "", content)
    content = re.sub(r"import 'package:flutter/services\.dart';\n", "", content)
    content = re.sub(r"import 'package:intl/intl\.dart';\n", "", content)

    # Re-add typed_data where needed if it contains Uint8List but no import
    if 'Uint8List' in content and "import 'dart:typed_data';" not in content:
        content = "import 'dart:typed_data';\n" + content
    return content

def fix_allowed_extensions(content):
    # allowedExtensions is used when picking files, but if it says "undefined named parameter", it means file_picker's pickFiles might not have it anymore or it's wrapped differently
    # Let's check file_picker 8.3.7 documentation or just remove allowedExtensions if not needed, but wait: file_picker FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zgl'])
    # Let's check how it's called.
    return content

def fix_deprecated(content):
    content = fix_with_opacity(content)

    def repl(m):
        return m.group(1) + "initialValue:"

    content = re.sub(r'(DropdownButtonFormField(?:<[^>]+>)?\s*\(\s*(?://[^\n]*\n\s*)*)(?:value\s*:)', repl, content)
    return content

def fix_ambiguous_inspection(content):
    return content.replace("import 'package:zegel/zegel.dart';", "import 'package:zegel/zegel.dart' hide ZegelInspection;")

for root, dirs, files in os.walk('app/lib'):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()

            new_content = fix_imports(content)
            new_content = fix_deprecated(new_content)

            if file == 'media_metadata_screen.dart':
                new_content = fix_ambiguous_inspection(new_content)

            if new_content != content:
                with open(filepath, 'w') as f:
                    f.write(new_content)

print("Fixed basic app issues.")

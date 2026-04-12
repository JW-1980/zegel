import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    modified = False

    if 'envelope_screen.dart' in filepath:
        content = re.sub(r'const DropdownMenuItem', r'DropdownMenuItem', content)
        content = content.replace("items: [", "items: const [")
        modified = True

    if 'split_key_screen.dart' in filepath:
        content = content.replace("Share.share(", "SharePlus.instance.share(ShareParams(text: ")
        content = content.replace("$_totalShares',\n                                );", "$_totalShares',\n                                ));")
        modified = True

    if 'key_service.dart' in filepath:
        content = content.replace("aOptions: AndroidOptions(encryptedSharedPreferences: true),", "aOptions: AndroidOptions(),")
        modified = True

    if modified:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)

for root, dirs, files in os.walk('app/lib'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))

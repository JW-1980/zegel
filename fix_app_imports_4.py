import os

files_to_fix = [
    'app/lib/screens/media_metadata_screen.dart',
    'app/lib/screens/canary_screen.dart',
    'app/lib/screens/disclose_screen.dart',
    'app/lib/screens/keygen_screen.dart',
]

for filepath in files_to_fix:
    if not os.path.exists(filepath):
        print(f"File {filepath} not found.")
        continue

    with open(filepath, 'r') as f:
        lines = f.readlines()

    with open(filepath, 'w') as f:
        for line in lines:
            if "import 'dart:typed_data';" not in line:
                f.write(line)

print("Done removing unnecessary imports.")

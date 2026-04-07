import re

# Fix Icons.share_off in lib/screens/keygen_screen.dart
with open('app/lib/screens/keygen_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("Icons.share_off", "Icons.share")

with open('app/lib/screens/keygen_screen.dart', 'w') as f:
    f.write(content)

# Fix lib/screens/media_metadata_screen.dart:115:25
with open('app/lib/screens/media_metadata_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("ZegelInspection _inspection;", "ZegelInspection? _inspection;")

with open('app/lib/screens/media_metadata_screen.dart', 'w') as f:
    f.write(content)

print("Fixed more app issues.")

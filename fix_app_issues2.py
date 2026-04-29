import sys
import re

with open("app/lib/screens/attest_screen.dart", "r") as f:
    content = f.read()

# Fix allowedExtensions issue. Let's just remove `allowedExtensions: ['zgl']` from `pickFiles`
# if it's there. Actually, file_picker pickFiles uses `type: FileType.custom, allowedExtensions: ['zgl']`
# Let's see how it's called. Wait, the error is `error • The named parameter 'allowedExtensions' isn't defined`
# in `lib/screens/attest_screen.dart:71:7`.
content = re.sub(r'allowedExtensions:\s*\[\'zgl\'\]\s*,?', '', content)

with open("app/lib/screens/attest_screen.dart", "w") as f:
    f.write(content)

# The tests fail because the `lib/pubspec.yaml` was originally on pointycastle 3.9.1, but maybe it requires 3.7.3 in some cases, or pointcastle 3.9.1 dropped Ed25519 APIs? Wait, Ed25519 was ADDED in pointycastle at some point, or maybe it is exported differently in 3.9.1?
# It doesn't matter for WetSignature parity. The system is telling me I must fully fix the pointycastle issue.

import re

with open("lib/pubspec.yaml", "r") as f:
    content = f.read()

content = content.replace("pointycastle: ^3.7.3", "pointycastle: ^3.9.1")

with open("lib/pubspec.yaml", "w") as f:
    f.write(content)

with open("cli/pubspec.yaml", "r") as f:
    content = f.read()

content = content.replace("pointycastle: ^3.7.3", "pointycastle: ^3.9.1")

with open("cli/pubspec.yaml", "w") as f:
    f.write(content)

# We need to change the imports in identity.dart and supply_chain.dart back to hide Digest, Signature and pointcastle 3.9.1

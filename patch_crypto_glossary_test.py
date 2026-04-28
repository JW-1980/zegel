import re

with open('lib/test/crypto_glossary_test.dart', 'r') as f:
    content = f.read()

# Add post-quantum-cryptography to known keys
content = content.replace("      'audit-trail',\n    ];", "      'audit-trail',\n      'post-quantum-cryptography',\n    ];")

with open('lib/test/crypto_glossary_test.dart', 'w') as f:
    f.write(content)

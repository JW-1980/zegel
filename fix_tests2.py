import os
import re

with open('lib/test/media_metadata_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const timestamp = DateTime", "final timestamp = DateTime")
with open('lib/test/media_metadata_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/provenance_verification_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const timestamp = DateTime", "final timestamp = DateTime")
with open('lib/test/provenance_verification_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/timestamp_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const timestamp = DateTime", "final timestamp = DateTime")
with open('lib/test/timestamp_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/writer_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const expiration = DateTime", "final expiration = DateTime")
with open('lib/test/writer_test.dart', 'w') as f:
    f.write(content)

with open('lib/lib/src/reader.dart', 'r') as f:
    content = f.read()

# Fix `disclosedIndices`
# I accidentally removed it earlier with:
# content = re.sub(r'final List<int> disclosedIndices = <int>\[\];\n', '', content)
# And then it complained `lib/src/reader.dart:607:24 - Undefined name 'disclosedIndices'`.
# Let's restore `final List<int> disclosedIndices = <int>[];` at the top of verify() or where it was.

# If we look at the original code or just add it back around line 300 where it was unused, but wait:
# If it's used at line 607, we need it to be declared before line 607 in the same function.

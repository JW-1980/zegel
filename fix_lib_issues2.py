import os
import re

with open('lib/lib/src/reader.dart', 'r') as f:
    content = f.read()
# Revert disclosedIndices removal because it was used later?
content = content.replace("disclosedIndices.add", "final List<int> disclosedIndices = <int>[];\n          disclosedIndices.add")
with open('lib/lib/src/reader.dart', 'w') as f:
    f.write(content)

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

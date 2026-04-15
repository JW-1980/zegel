import re

with open('lib/test/provenance_verification_test.dart', 'r') as f:
    content = f.read()

# Let's fix line 40-42
# 40: const variables must be initialized with a constant value.
# Let's just find `const ` and replace with `final ` globally in this file where it might be `DateTime` or `ProvenanceEvent`.
content = content.replace("const ", "final ")

with open('lib/test/provenance_verification_test.dart', 'w') as f:
    f.write(content)


with open('lib/test/timestamp_test.dart', 'r') as f:
    lines = f.readlines()

# Replace const with final on line 161 to fix constant value initialization error.
if len(lines) >= 161:
    lines[160] = lines[160].replace("const ", "final ")

with open('lib/test/timestamp_test.dart', 'w') as f:
    f.writelines(lines)


with open('lib/test/writer_test.dart', 'r') as f:
    content = f.read()

# Let's fix line 192 and 207
content = content.replace("const ZegelOptions(", "final ZegelOptions(")
# Wait, let's just globally replace "const ZegelOptions(" with "final ZegelOptions("
# if the const isn't needed. Or remove `const` keyword on those lines.
# We replaced "const options = ZegelOptions(" before, maybe it was "final options = const ZegelOptions"?
content = content.replace("= const ZegelOptions(", "= ZegelOptions(")

with open('lib/test/writer_test.dart', 'w') as f:
    f.write(content)

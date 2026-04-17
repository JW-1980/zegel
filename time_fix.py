import re

with open("lib/test/timestamp_test.dart", "r") as f:
    text = f.read()

# Did we accidentally revert test/timestamp_test.dart where it used const?
# I saw `const timestamp = ByteData.sublistView(` in `test/writer_test.dart` and similar const issues.

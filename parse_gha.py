import sys

# The GHA tests failed, let's see which test file.
# "2026-04-17T17:22:40.4812479Z ##[error]1277 tests passed, 9 failed."
# I didn't see the failures in my `grep` because GitHub Actions truncates successful tests and the failures are somewhere in the middle, or the tool didn't show them because they were before the truncation.

# What tests have time dependency?
# `test/temp_file_cleanup_test.dart` uses `Future.delayed(const Duration(seconds: 1));` maybe?
with open("lib/test/temp_file_cleanup_test.dart", "r") as f:
    text = f.read()

import re
for line in text.split("\n"):
    if "Future.delayed" in line or "setLastModified" in line:
        print(line)

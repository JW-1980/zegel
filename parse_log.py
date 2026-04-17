import re

with open("lib/test_output.log", "r") as f:
    text = f.read()

import sys
for line in text.split("\n"):
    if "-1:" in line or "-2:" in line or "-3:" in line or "-4:" in line or "-5:" in line or "-6:" in line or "-7:" in line or "-8:" in line or "-9:" in line or "-10:" in line:
        print(line)

    if "Failed to load" in line:
        print(line)

    if "tests failed." in line:
        print(line)

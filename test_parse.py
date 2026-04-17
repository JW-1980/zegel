import re

with open("lib/test_output.log", "r") as f:
    text = f.read()

lines = text.split('\n')
for line in lines:
    if "Failed" in line or "failed" in line.lower() or "Exception" in line or "error" in line.lower():
        pass # ignore expected text like "returns error"

    if "-1" in line or "-2" in line or "-3" in line or "-4" in line:
        pass # just checking

print("All tests passed!" in text)

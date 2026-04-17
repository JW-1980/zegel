import re

with open("lib/test_output.log", "r") as f:
    text = f.read()

# is there any text saying "Failed"?
print("Failed" in text)

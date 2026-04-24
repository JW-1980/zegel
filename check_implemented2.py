import re
import os
import subprocess

with open('RECOMMENDATIONS.md', 'r') as f:
    text = f.read()

# get the section up to "15 Items"
idx = text.find("## 15 Items")
if idx != -1:
    text = text[:idx]

matches = re.findall(r'^(\d+)\.\s+(.*)$', text, re.MULTILINE)
items = [m for m in matches if int(m[0]) <= 100]

implemented = []
not_implemented = []

# Simple heuristic check, let's just do a manual inspection since script is imperfect
for num, desc in items:
    print(f"{num}. {desc}")

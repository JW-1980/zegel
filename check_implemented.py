import re
import os
import subprocess

with open('RECOMMENDATIONS.md', 'r') as f:
    text = f.read()

matches = re.findall(r'^(\d+)\.\s+(.*)$', text, re.MULTILINE)
items = [m for m in matches if int(m[0]) <= 100]

implemented = []
not_implemented = []

for num, desc in items:
    words = [w.lower() for w in re.findall(r'[A-Za-z]{5,}', desc)]
    found = False
    for word in words:
        if word in ['their', 'there', 'which', 'would', 'could', 'feature', 'system', 'support', 'custom', 'customizable']: continue
        try:
            res = subprocess.run(['grep', '-ir', word, 'app/lib', 'lib/lib'], capture_output=True, text=True)
            if len(res.stdout.splitlines()) > 1:
                found = True
                break
        except:
            pass
    if found:
        implemented.append((num, desc))
    else:
        not_implemented.append((num, desc))

print(f"Implemented: {len(implemented)}")
print(f"Not implemented: {len(not_implemented)}")
for n, d in not_implemented:
    print(f"{n}. {d}")

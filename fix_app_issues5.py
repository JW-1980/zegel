import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')
    for i, line in enumerate(lines):
        if line.strip().startswith('///'):
            lines[i] = line.replace('<', '&lt;').replace('>', '&gt;')

    content = '\n'.join(lines)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

for root, dirs, files in os.walk('cli/lib/commands'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))

print("Fixed doc comments")

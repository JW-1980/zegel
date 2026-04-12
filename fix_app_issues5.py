import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.split('\n')

    if 'comprehensive_tamper_test.dart' in filepath:
        # replace unused variables
        # final ZegelInspection aInspection = reader.inspect(bytes);
        # replace it with just: reader.inspect(bytes);
        content = content.replace("reader.inspect(bytes);", "")

    if 'security_fixes_test.dart' in filepath:
        content = content.replace("reader.inspect(bytes);", "")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

for root, dirs, files in os.walk('lib/test'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))

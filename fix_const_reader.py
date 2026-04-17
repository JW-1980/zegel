import os

for root, dirs, files in os.walk('lib/test'):
    for file in files:
        if file.endswith('.dart'):
            with open(os.path.join(root, file), 'r') as f:
                content = f.read()
            content = content.replace("const const ZegelReader()", "const ZegelReader()")
            with open(os.path.join(root, file), 'w') as f:
                f.write(content)

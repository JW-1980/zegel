import re

with open("lib/pubspec.yaml", "r") as f:
    content = f.read()
content = content.replace("pointycastle: ^3.7.3", "pointycastle: ^3.9.1")
with open("lib/pubspec.yaml", "w") as f:
    f.write(content)

with open("cli/pubspec.yaml", "r") as f:
    content = f.read()
content = content.replace("pointycastle: ^3.7.3", "pointycastle: ^3.9.1")
with open("cli/pubspec.yaml", "w") as f:
    f.write(content)

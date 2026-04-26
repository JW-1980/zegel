import sys

content = ""
with open("lib/test/reveal_in_os_test.dart", "r") as f:
    content = f.read()

# Instead of hardcoding C:\, use context.
content = content.replace("r'C:\Users\\alice\secret.zgl'", "File('C:/Users/alice/secret.zgl').absolute.path.replaceAll('/', '\\\\')")
content = content.replace("r'C:\My Documents\\report.zgl'", "File('C:/My Documents/report.zgl').absolute.path.replaceAll('/', '\\\\')")

# For macos and linux, test absolute paths.
content = content.replace("const path = '/Users/alice/Documents/secret.zgl';", "final path = '/Users/alice/Documents/secret.zgl';")
content = content.replace("const path = '/home/alice/docs/secret.zgl';", "final path = '/home/alice/docs/secret.zgl';")

with open("lib/test/reveal_in_os_test.dart", "w") as f:
    f.write(content)

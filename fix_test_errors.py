with open('lib/test/timestamp_test.dart', 'r') as f:
    content = f.read()

content = content.replace("const timestamp = DateTime", "final timestamp = DateTime")

with open('lib/test/timestamp_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/writer_test.dart', 'r') as f:
    content = f.read()

# Lines 192, 207:
# const sealOptions = ZegelOptions(expiration: DateTime.now().add(const Duration(days: 30)));
# Or something similar.
content = content.replace("const expiration = DateTime", "final expiration = DateTime")
content = content.replace("const options = ZegelOptions(expiration: expiration)", "final options = ZegelOptions(expiration: expiration)")

# Let's just find `const ZegelOptions` and replace it with `ZegelOptions` if it contains `expiration`
content = content.replace("const sealOptions = ZegelOptions(expiration: expiration);", "final sealOptions = ZegelOptions(expiration: expiration);")
content = content.replace("const sealOptions = ZegelOptions(regulatoryHold: holdDate);", "final sealOptions = ZegelOptions(regulatoryHold: holdDate);")


with open('lib/test/writer_test.dart', 'w') as f:
    f.write(content)

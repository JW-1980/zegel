with open('lib/test/timestamp_test.dart', 'r') as f:
    content = f.read()
content = content.replace("final inspection = final ZegelReader().inspect(fileBytes);", "final inspection = const ZegelReader().inspect(fileBytes);")
with open('lib/test/timestamp_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/writer_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const timestamp = ByteData.sublistView(fileBytes, 12, 20)", "final timestamp = ByteData.sublistView(fileBytes, 12, 20)")
with open('lib/test/writer_test.dart', 'w') as f:
    f.write(content)

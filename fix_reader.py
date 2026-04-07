with open('lib/lib/src/reader.dart', 'r') as f:
    content = f.read()

content = content.replace("disclosedBlocks: disclosedIndices,", "disclosedBlocks: null,")

with open('lib/lib/src/reader.dart', 'w') as f:
    f.write(content)

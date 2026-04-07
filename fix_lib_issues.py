import os
import re

def process_lib_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # unused disclosedIndices
    if 'reader.dart' in filepath:
        content = re.sub(r'final List<int> disclosedIndices = <int>\[\];\n', '', content)

    if 'batch.dart' in filepath:
        content = content.replace("ZegelReader()", "const ZegelReader()")

    if 'classification.dart' in filepath:
        content = content.replace("ZegelReader()", "const ZegelReader()")

    if 'excerpt.dart' in filepath:
        content = content.replace("(index) => b.indices.contains(index)", "b.indices.contains")

    if 'hierarchical_split_key.dart' in filepath:
        content = content.replace("Uint8List xorAccumulator =", "final Uint8List xorAccumulator =")
        content = content.replace("Uint8List masterKey =", "final Uint8List masterKey =")

    if 'writer.dart' in filepath:
        content = content.replace("ZegelReader()", "const ZegelReader()")

    with open(filepath, 'w') as f:
        f.write(content)

for root, dirs, files in os.walk('lib/lib'):
    for file in files:
        if file.endswith('.dart'):
            process_lib_file(os.path.join(root, file))

for root, dirs, files in os.walk('lib/test'):
    for file in files:
        if file.endswith('.dart'):
            with open(os.path.join(root, file), 'r') as f:
                content = f.read()
            content = content.replace("ZegelReader()", "const ZegelReader()")
            content = content.replace("(b) => b.type == ZegelFormat.blockRedacted", "isRedactedBlock")
            content = content.replace("final expiration =", "const expiration =")
            content = content.replace("final timestamp =", "const timestamp =")
            content = content.replace("(b) => b.type == ZegelFormat.blockRedacted", "isRedactedBlock")
            with open(os.path.join(root, file), 'w') as f:
                f.write(content)

print("Fixed lib issues.")

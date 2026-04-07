with open("lib/lib/src/identity.dart", "r") as f:
    content = f.read()

content = content.replace("import 'package:pointycastle/export.dart';", "import 'package:pointycastle/export.dart' hide Digest, Signature;")
content = content.replace("import 'package:crypto/crypto.dart';", "import 'package:crypto/crypto.dart' as crypto;")

with open("lib/lib/src/identity.dart", "w") as f:
    f.write(content)

with open("lib/lib/src/supply_chain.dart", "r") as f:
    content = f.read()

content = content.replace("import 'package:pointycastle/export.dart';", "import 'package:pointycastle/export.dart' hide Digest, Signature;")
content = content.replace("import 'package:crypto/crypto.dart';", "import 'package:crypto/crypto.dart' as crypto;")
content = content.replace("class AccumulatorSink<T> implements Sink<T> {", "class AccumulatorSink<T> implements Sink<crypto.Digest> {")

with open("lib/lib/src/supply_chain.dart", "w") as f:
    f.write(content)


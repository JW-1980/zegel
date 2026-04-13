import 'dart:io';

void main() {
  final file = File('lib/lib/src/reader.dart');
  String content = file.readAsStringSync();
  content = content.replaceFirst(
    "final Set<int> disclosedIndices = <int>{};",
    "// final Set<int> disclosedIndices = <int>{};",
  );
  file.writeAsStringSync(content);
}

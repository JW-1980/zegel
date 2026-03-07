import 'dart:io';

void main() {
  final file = File('cli/lib/commands/batch_command.dart');
  String content = file.readAsStringSync();
  content = content.replaceFirst("final bool verbose = globalResults?['verbose'] as bool ?? false;", "// final bool verbose = globalResults?['verbose'] as bool ?? false;");
  file.writeAsStringSync(content);

  final file2 = File('cli/lib/commands/canary_command.dart');
  String content2 = file2.readAsStringSync();
  content2 = content2.replaceFirst("final ZegelResult result = reader.verify(bytes, key);", "reader.verify(bytes, key);");
  file2.writeAsStringSync(content2);

  final file3 = File('cli/lib/commands/excerpt_command.dart');
  String content3 = file3.readAsStringSync();
  content3 = content3.replaceFirst("final Uint8List key = await KeyManagement.getKey(", "await KeyManagement.getKey(");
  file3.writeAsStringSync(content3);
}

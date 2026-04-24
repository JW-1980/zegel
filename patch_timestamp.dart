import 'dart:io';

void main() {
  final file = File('lib/lib/src/timestamp.dart');
  var content = file.readAsStringSync();

  content = content.replaceFirst(
'''
  @Deprecated('Use fetchRoughtime or fetchRfc3161 for authoritative timestamps')
  static Map<String, dynamic> createLocalToken(
''',
'''
  static Map<String, dynamic> createLocalToken(
'''
  );

  content = content.replaceFirst(
'''
  @Deprecated('Local tokens are self-asserted and non-authoritative')
  static bool verifyLocalToken(
''',
'''
  static bool verifyLocalToken(
'''
  );

  file.writeAsStringSync(content);
}

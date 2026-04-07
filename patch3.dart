import 'dart:io';

void main() {
  var file = File('app/lib/screens/canary_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('final path = await fileService.pickFile(\n      allowedExtensions: [\'zgl\'],\n    );', 'final path = await fileService.pickZegelFile();');
  file.writeAsStringSync(content);

  file = File('app/lib/screens/audit_screen.dart');
  content = file.readAsStringSync();
  content = content.replaceAll('final path = await fileService.pickFile(\n      allowedExtensions: [\'zgl\'],\n    );', 'final path = await fileService.pickZegelFile();');
  file.writeAsStringSync(content);

  file = File('app/lib/screens/attest_screen.dart');
  content = file.readAsStringSync();
  content = content.replaceAll('final path = await fileService.pickFile(\n      allowedExtensions: [\'zgl\'],\n    );', 'final path = await fileService.pickZegelFile();');
  file.writeAsStringSync(content);
}

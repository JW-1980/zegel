import 'dart:io';

void main() {
  var file = File('app/lib/screens/media_metadata_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('import \'../services/zegel_service.dart\';', 'import \'../services/zegel_service.dart\' hide ZegelInspection;');
  file.writeAsStringSync(content);
}

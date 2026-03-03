import 'dart:io';

void main() {
  var file = File('app/lib/screens/timestamp_screen.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('cursor += 4 + pubMetaLen;', 'cursor += (4 + pubMetaLen).toInt();');
  content = content.replaceAll('cursor += blockCount * ZegelFormat.blockDirectoryEntrySize;', 'cursor += (blockCount * ZegelFormat.blockDirectoryEntrySize).toInt();');
  file.writeAsStringSync(content);

  file = File('app/lib/screens/version_chain_screen.dart');
  content = file.readAsStringSync();
  content = content.replaceAll('cursor += blockCount * ZegelFormat.blockDirectoryEntrySize;', 'cursor += (blockCount * ZegelFormat.blockDirectoryEntrySize).toInt();');
  file.writeAsStringSync(content);
}

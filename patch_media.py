with open('app/lib/screens/media_metadata_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("import '../services/zegel_service.dart' hide ZegelInspection, ZegelResult;", "import '../services/zegel_service.dart';")
content = content.replace("import 'package:zegel/zegel.dart';", "import 'package:zegel/zegel.dart' hide ZegelInspection, ZegelResult;")

with open('app/lib/screens/media_metadata_screen.dart', 'w') as f:
    f.write(content)
print("Done")

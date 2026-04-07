with open('app/lib/screens/media_metadata_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("import '../services/zegel_service.dart';", "")

with open('app/lib/screens/media_metadata_screen.dart', 'w') as f:
    f.write(content)

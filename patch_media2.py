with open('app/lib/screens/media_metadata_screen.dart', 'r') as f:
    content = f.read()

# We need the zegel_service versions of ZegelInspection probably, actually we should check where `reader.inspect` comes from.
# `final reader = const ZegelReader();` returns `package:zegel/src/reader.dart`'s `ZegelInspection`.
# So we need `ZegelInspection` from `package:zegel/zegel.dart`!
# But wait, `app/lib/services/zegel_service.dart` also defines `class ZegelInspection`.
# So we must hide `ZegelInspection` from `zegel_service.dart`, NOT `package:zegel/zegel.dart`.

content = content.replace("import '../services/zegel_service.dart';", "import '../services/zegel_service.dart' hide ZegelInspection, ZegelResult;")
content = content.replace("import 'package:zegel/zegel.dart' hide ZegelInspection, ZegelResult;", "import 'package:zegel/zegel.dart';")

with open('app/lib/screens/media_metadata_screen.dart', 'w') as f:
    f.write(content)
print("Done again")

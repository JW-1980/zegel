with open('lib/test/media_metadata_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const timestamp = entry['timestamp'] as int;", "final timestamp = entry['timestamp'] as int;")
with open('lib/test/media_metadata_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/provenance_verification_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const event1 = ProvenanceEvent", "final event1 = ProvenanceEvent")
content = content.replace("const event2 = ProvenanceEvent", "final event2 = ProvenanceEvent")
content = content.replace("const options = ZegelOptions", "final options = ZegelOptions")
content = content.replace("const sealOptions = ZegelOptions", "final sealOptions = ZegelOptions")
with open('lib/test/provenance_verification_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/timestamp_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const info = TimestampInfo", "final info = TimestampInfo")
content = content.replace("const now = DateTime", "final now = DateTime")
with open('lib/test/timestamp_test.dart', 'w') as f:
    f.write(content)

with open('lib/test/writer_test.dart', 'r') as f:
    content = f.read()
content = content.replace("const options = ZegelOptions(", "final options = ZegelOptions(")
content = content.replace("const expiration = DateTime", "final expiration = DateTime")
with open('lib/test/writer_test.dart', 'w') as f:
    f.write(content)

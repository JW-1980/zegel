import os

def read_file(path):
    with open(path, 'r') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w') as f:
        f.write(content)

c = read_file('lib/test/media_metadata_test.dart')
c = c.replace("const timestamp = DateTime", "final timestamp = DateTime")
write_file('lib/test/media_metadata_test.dart', c)

c = read_file('lib/test/provenance_verification_test.dart')
c = c.replace("const timestamp = DateTime", "final timestamp = DateTime")
c = c.replace("const event1 = ProvenanceEvent", "final event1 = ProvenanceEvent")
c = c.replace("const event2 = ProvenanceEvent", "final event2 = ProvenanceEvent")
write_file('lib/test/provenance_verification_test.dart', c)

c = read_file('lib/test/timestamp_test.dart')
c = c.replace("const timestamp = DateTime", "final timestamp = DateTime")
c = c.replace("const info = TimestampInfo", "final info = TimestampInfo")
write_file('lib/test/timestamp_test.dart', c)

c = read_file('lib/test/writer_test.dart')
c = c.replace("const expiration = DateTime", "final expiration = DateTime")
c = c.replace("const options = ZegelOptions", "final options = ZegelOptions")
write_file('lib/test/writer_test.dart', c)

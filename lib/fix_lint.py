import re

def fix(path):
    with open(path, 'r') as f:
        content = f.read()

    # Apply proper replacements for the structured_blocks.dart tests in security_fixes_test.dart

    content = content.replace("MeasurementReading(", "MeasurementBlock(")
    content = content.replace("PrivilegeLogEntry(", "RedactionBasis(")

    # Fix the missing parameter `readings` inside `MeasurementBlock` etc.
    # Replace the outer `MeasurementBlock(readings: [MeasurementBlock(...)])` with just `MeasurementBlock(...)`
    content = re.sub(
        r'final measurement = const MeasurementBlock\(\s*readings: \[\s*const MeasurementBlock\([\s\S]*?deviceId: \'logger-XYZ\',\s*deviceModel: \'TempLogger Pro\',\s*\);',
        '''final measurement = const MeasurementBlock(
        timestamp: 1700000000,
        sensorId: 'temp-sensor-01',
        value: 2.5,
        unit: 'celsius',
        location: '52.3676,4.9041',
        batchId: 'logger-XYZ',
      );''',
        content, flags=re.DOTALL
    )

    content = re.sub(
        r'final privilegeLog = const PrivilegeLogBlock\(\s*entries: \[\s*const RedactionBasis\([\s\S]*?caseTitle: \'ACME v\. State\',\s*jurisdiction: \'US Federal\',\s*\);',
        '''final privilegeLog = const PrivilegeLogBlock(
        entries: [
          const RedactionBasis(
            blockIndex: 3,
            legalAuthority: 'FOIA Exemption 5',
            reason: 'Deliberative process privilege',
            date: 1700000000,
            authorisedBy: 'J. Smith, Esq.',
          ),
        ],
        caseTitle: 'ACME v. State',
      );''',
        content, flags=re.DOTALL
    )

    content = content.replace("expect(decoded.readings.length, equals(1));\n", "")
    content = content.replace("expect(decoded.readings[0].value, equals(2.5));", "expect(decoded.value, equals(2.5));")
    content = content.replace("expect(decoded.readings[0].unit, equals('celsius'));", "expect(decoded.unit, equals('celsius'));")
    content = content.replace("expect(decoded.readings[0].location!['lat'], equals(52.3676));", "expect(decoded.location, equals('52.3676,4.9041'));")
    content = content.replace("expect(decoded.deviceId, equals('logger-XYZ'));", "expect(decoded.batchId, equals('logger-XYZ'));")

    content = content.replace("expect(decoded.jurisdiction, equals('US Federal'));\n", "")

    with open(path, 'w') as f:
        f.write(content)

fix('test/security_fixes_test.dart')

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('Envelope basics', () {
    test('creates envelope with recipients', () {
      final envelope = Envelope(
        id: 'env-001',
        subject: 'NDA for vendor onboarding',
        senderName: 'Alice',
        senderEmail: 'alice@example.com',
        recipients: [
          EnvelopeRecipient(
            id: 'rcpt-1',
            name: 'Bob',
            email: 'bob@example.com',
            role: RecipientRole.signer,
            routingOrder: 1,
          ),
          EnvelopeRecipient(
            id: 'rcpt-2',
            name: 'Carol',
            email: 'carol@example.com',
            role: RecipientRole.signer,
            routingOrder: 2,
          ),
        ],
      );

      expect(envelope.id, equals('env-001'));
      expect(envelope.recipients.length, equals(2));
      expect(envelope.status, equals(EnvelopeStatus.draft));
    });

    test('encode/decode roundtrip', () {
      final envelope = Envelope(
        id: 'env-roundtrip',
        subject: 'Test roundtrip',
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'Alice',
            email: 'alice@test.com',
            role: RecipientRole.signer,
          ),
        ],
      );

      final encoded = envelope.encode();
      final decoded = Envelope.decode(encoded);

      expect(decoded.id, equals(envelope.id));
      expect(decoded.subject, equals(envelope.subject));
      expect(decoded.recipients.length, equals(1));
      expect(decoded.recipients[0].name, equals('Alice'));
    });

    test('sequential routing returns first incomplete recipient', () {
      final envelope = Envelope(
        id: 'env-seq',
        subject: 'Sequential test',
        routingMode: RoutingMode.sequential,
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'First',
            email: 'first@test.com',
            role: RecipientRole.signer,
            routingOrder: 1,
            status: RecipientStatus.signed,
          ),
          EnvelopeRecipient(
            id: 'r2',
            name: 'Second',
            email: 'second@test.com',
            role: RecipientRole.signer,
            routingOrder: 2,
            status: RecipientStatus.sent,
          ),
          EnvelopeRecipient(
            id: 'r3',
            name: 'Third',
            email: 'third@test.com',
            role: RecipientRole.signer,
            routingOrder: 3,
            status: RecipientStatus.created,
          ),
        ],
      );

      final current = envelope.currentRecipients();
      expect(current.length, equals(1));
      expect(current[0].id, equals('r2'));
    });

    test('parallel routing returns all incomplete recipients', () {
      final envelope = Envelope(
        id: 'env-par',
        subject: 'Parallel test',
        routingMode: RoutingMode.parallel,
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'A',
            email: 'a@test.com',
            role: RecipientRole.signer,
            status: RecipientStatus.signed,
          ),
          EnvelopeRecipient(
            id: 'r2',
            name: 'B',
            email: 'b@test.com',
            role: RecipientRole.signer,
            status: RecipientStatus.sent,
          ),
          EnvelopeRecipient(
            id: 'r3',
            name: 'C',
            email: 'c@test.com',
            role: RecipientRole.signer,
            status: RecipientStatus.sent,
          ),
        ],
      );

      final current = envelope.currentRecipients();
      expect(current.length, equals(2));
      expect(current.map((r) => r.id).toList(), containsAll(['r2', 'r3']));
    });

    test('isFullySigned ignores CC recipients', () {
      final envelope = Envelope(
        id: 'env-cc',
        subject: 'CC test',
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'Signer',
            email: 's@test.com',
            role: RecipientRole.signer,
            status: RecipientStatus.signed,
          ),
          EnvelopeRecipient(
            id: 'r2',
            name: 'Copy',
            email: 'c@test.com',
            role: RecipientRole.cc,
            status: RecipientStatus.created, // CC hasn't been "processed"
          ),
        ],
      );

      expect(envelope.isFullySigned(), isTrue);
    });

    test('audit chain: events are hash-linked', () {
      final envelope = Envelope(
        id: 'env-audit',
        subject: 'Audit chain test',
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'Alice',
            email: 'a@test.com',
            role: RecipientRole.signer,
          ),
        ],
      );

      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1000,
        eventType: 'envelope_created',
        description: 'Envelope created',
      ));
      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1001,
        eventType: 'envelope_sent',
        description: 'Envelope sent to recipients',
      ));
      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1002,
        eventType: 'recipient_signed',
        description: 'Alice signed',
        recipientId: 'r1',
      ));

      expect(envelope.events.length, equals(3));
      expect(envelope.events[0].previousHash, isNull);
      expect(envelope.events[1].previousHash, isNotNull);
      expect(envelope.events[2].previousHash, isNotNull);
      expect(envelope.verifyAuditChain(), isTrue);
    });

    test('audit chain detects tampered event', () {
      final envelope = Envelope(
        id: 'env-tamper',
        subject: 'Tamper test',
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'X',
            email: 'x@test.com',
            role: RecipientRole.signer,
          ),
        ],
      );

      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1000,
        eventType: 'envelope_created',
        description: 'Original',
      ));
      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1001,
        eventType: 'envelope_sent',
        description: 'Sent',
      ));

      // Tamper: replace first event with a different description.
      envelope.events[0] = const EnvelopeEvent(
        timestamp: 1000,
        eventType: 'envelope_created',
        description: 'TAMPERED',
      );

      expect(envelope.verifyAuditChain(), isFalse);
    });

    test('isExpired returns true when past expiration', () {
      final past = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 3600;
      final envelope = Envelope(
        id: 'env-exp',
        subject: 'Expired',
        expiresAt: past,
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'X',
            email: 'x@test.com',
            role: RecipientRole.signer,
          ),
        ],
      );

      expect(envelope.isExpired(), isTrue);
    });
  });

  group('SignatureField', () {
    test('encode/decode roundtrip', () {
      const field = SignatureField(
        id: 'sig-1',
        type: FieldType.signature,
        recipientId: 'r1',
        page: 0,
        x: 100,
        y: 200,
        width: 150,
        height: 50,
        label: 'Signature',
      );

      final json = field.toJson();
      final decoded = SignatureField.fromJson(json);

      expect(decoded.id, equals('sig-1'));
      expect(decoded.type, equals(FieldType.signature));
      expect(decoded.x, equals(100));
      expect(decoded.label, equals('Signature'));
    });

    test('supports dropdown options', () {
      const field = SignatureField(
        id: 'sel-1',
        type: FieldType.dropdown,
        recipientId: 'r1',
        page: 0,
        x: 0,
        y: 0,
        options: ['Option A', 'Option B', 'Option C'],
      );

      final json = field.toJson();
      final decoded = SignatureField.fromJson(json);

      expect(decoded.options, equals(['Option A', 'Option B', 'Option C']));
    });
  });

  group('Template instantiation', () {
    test('template with two roles instantiates to envelope', () {
      const template = EnvelopeTemplate(
        id: 'tmpl-1',
        name: 'Buyer/Seller Contract',
        subject: 'Real estate contract',
        roles: [
          TemplateRole(
            roleId: 'buyer',
            roleName: 'Buyer',
            recipientRole: RecipientRole.signer,
            routingOrder: 1,
          ),
          TemplateRole(
            roleId: 'seller',
            roleName: 'Seller',
            recipientRole: RecipientRole.signer,
            routingOrder: 2,
          ),
        ],
        fields: [
          TemplateField(
            id: 'sig-buyer',
            type: FieldType.signature,
            roleId: 'buyer',
            page: 0,
            x: 100,
            y: 500,
          ),
          TemplateField(
            id: 'sig-seller',
            type: FieldType.signature,
            roleId: 'seller',
            page: 0,
            x: 300,
            y: 500,
          ),
        ],
      );

      final envelope = template.instantiate(
        envelopeId: 'env-contract-001',
        roleMapping: {
          'buyer': const TemplateRoleMapping(
            name: 'John Doe',
            email: 'john@example.com',
          ),
          'seller': const TemplateRoleMapping(
            name: 'Jane Smith',
            email: 'jane@example.com',
          ),
        },
        documentMerkleRoots: ['abc123'],
      );

      expect(envelope.id, equals('env-contract-001'));
      expect(envelope.recipients.length, equals(2));
      expect(envelope.recipients[0].name, equals('John Doe'));
      expect(envelope.recipients[1].name, equals('Jane Smith'));
      expect(envelope.fields.length, equals(2));
      // Fields should be mapped to real recipient IDs.
      expect(envelope.fields[0].recipientId, equals(envelope.recipients[0].id));
      expect(envelope.fields[1].recipientId, equals(envelope.recipients[1].id));
    });

    test('instantiation fails when a role is unmapped', () {
      const template = EnvelopeTemplate(
        id: 'tmpl-2',
        name: 'Missing role',
        subject: 'Test',
        roles: [
          TemplateRole(
            roleId: 'a',
            roleName: 'A',
            recipientRole: RecipientRole.signer,
          ),
          TemplateRole(
            roleId: 'b',
            roleName: 'B',
            recipientRole: RecipientRole.signer,
          ),
        ],
        fields: [],
      );

      expect(
        () => template.instantiate(
          envelopeId: 'env-bad',
          roleMapping: {
            'a': const TemplateRoleMapping(
              name: 'X',
              email: 'x@test.com',
            ),
            // 'b' is missing!
          },
          documentMerkleRoots: [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('template encode/decode roundtrip', () {
      const template = EnvelopeTemplate(
        id: 'tmpl-rt',
        name: 'Roundtrip Test',
        subject: 'Test Template',
        description: 'A test template',
        tags: ['test', 'example'],
        roles: [
          TemplateRole(
            roleId: 'signer',
            roleName: 'Signer',
            recipientRole: RecipientRole.signer,
          ),
        ],
        fields: [
          TemplateField(
            id: 'f1',
            type: FieldType.signature,
            roleId: 'signer',
            page: 0,
            x: 100,
            y: 100,
          ),
        ],
      );

      final encoded = template.encode();
      final decoded = EnvelopeTemplate.decode(encoded);

      expect(decoded.id, equals('tmpl-rt'));
      expect(decoded.name, equals('Roundtrip Test'));
      expect(decoded.tags, equals(['test', 'example']));
      expect(decoded.roles.length, equals(1));
      expect(decoded.fields.length, equals(1));
    });
  });

  group('Certificate of Completion', () {
    test('generates certificate from completed envelope', () {
      final envelope = Envelope(
        id: 'env-complete',
        subject: 'Completed test',
        status: EnvelopeStatus.completed,
        senderName: 'Alice',
        senderEmail: 'alice@test.com',
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'Bob',
            email: 'bob@test.com',
            role: RecipientRole.signer,
            status: RecipientStatus.signed,
            signedAt: 1700000000,
            ipAddress: '192.0.2.1',
          ),
        ],
        createdAt: 1699999000,
        sentAt: 1699999500,
        completedAt: 1700000000,
      );

      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1699999000,
        eventType: 'envelope_created',
        description: 'Created',
      ));
      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1699999500,
        eventType: 'envelope_sent',
        description: 'Sent',
      ));
      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1700000000,
        eventType: 'envelope_completed',
        description: 'All signatures collected',
      ));

      final cert = CertificateOfCompletion.generate(envelope);

      expect(cert.envelopeId, equals('env-complete'));
      expect(cert.envelopeStatus, equals(EnvelopeStatus.completed));
      expect(cert.recipients.length, equals(1));
      expect(cert.events.length, equals(3));
      expect(cert.certificateHash, isNotNull);
      expect(cert.verify(), isTrue);
    });

    test('detects tampered certificate', () {
      final envelope = Envelope(
        id: 'env-tampered-cert',
        subject: 'Test',
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'X',
            email: 'x@test.com',
            role: RecipientRole.signer,
            status: RecipientStatus.signed,
          ),
        ],
      );
      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1000,
        eventType: 'a',
        description: 'a',
      ));

      final cert = CertificateOfCompletion.generate(envelope);

      // Tamper: construct a new certificate with the old hash but different content.
      final tampered = CertificateOfCompletion(
        envelopeId: 'DIFFERENT',
        envelopeSubject: cert.envelopeSubject,
        envelopeStatus: cert.envelopeStatus,
        recipients: cert.recipients,
        events: cert.events,
        documentMerkleRoots: cert.documentMerkleRoots,
        generatedAt: cert.generatedAt,
        certificateHash: cert.certificateHash,
      );

      expect(tampered.verify(), isFalse);
    });

    test('renders human-readable text', () {
      final envelope = Envelope(
        id: 'env-render',
        subject: 'NDA for vendor',
        status: EnvelopeStatus.completed,
        senderName: 'Alice Smith',
        senderEmail: 'alice@example.com',
        recipients: [
          EnvelopeRecipient(
            id: 'r1',
            name: 'Bob Jones',
            email: 'bob@vendor.com',
            role: RecipientRole.signer,
            status: RecipientStatus.signed,
            signedAt: 1700000000,
          ),
        ],
      );
      envelope.appendEvent(const EnvelopeEvent(
        timestamp: 1699999000,
        eventType: 'envelope_created',
        description: 'Envelope created by Alice Smith',
      ));

      final cert = CertificateOfCompletion.generate(envelope);
      final text = cert.renderText();

      expect(text, contains('CERTIFICATE OF COMPLETION'));
      expect(text, contains('env-render'));
      expect(text, contains('NDA for vendor'));
      expect(text, contains('Bob Jones'));
      expect(text, contains('bob@vendor.com'));
      expect(text, contains('envelope_created'));
    });
  });

  group('Bulk send', () {
    test('parses CSV recipient list', () {
      final csv = '''name,email,company,employee_id
Alice,alice@test.com,Acme,E001
Bob,bob@test.com,Acme,E002
Carol,carol@test.com,Acme,E003
''';
      final recipients = BulkRecipient.parseCsv(
        Uint8List.fromList(utf8.encode(csv)),
      );

      expect(recipients.length, equals(3));
      expect(recipients[0].name, equals('Alice'));
      expect(recipients[0].email, equals('alice@test.com'));
      expect(recipients[0].company, equals('Acme'));
      expect(recipients[0].customFields['employee_id'], equals('E001'));
    });

    test('creates bulk send job from template', () {
      const template = EnvelopeTemplate(
        id: 'tmpl-bulk',
        name: 'Policy Acknowledgment',
        subject: 'Please review the company policy',
        roles: [
          TemplateRole(
            roleId: 'employee',
            roleName: 'Employee',
            recipientRole: RecipientRole.signer,
          ),
        ],
        fields: [
          TemplateField(
            id: 'sig',
            type: FieldType.signature,
            roleId: 'employee',
            page: 0,
            x: 100,
            y: 500,
          ),
        ],
      );

      final recipients = [
        const BulkRecipient(name: 'Alice', email: 'alice@test.com'),
        const BulkRecipient(name: 'Bob', email: 'bob@test.com'),
        const BulkRecipient(name: 'Carol', email: 'carol@test.com'),
      ];

      final job = BulkSendJob.fromTemplate(
        jobId: 'bulk-001',
        template: template,
        signerRoleId: 'employee',
        recipients: recipients,
        documentMerkleRoots: ['doc-hash'],
        senderName: 'HR',
        senderEmail: 'hr@company.com',
      );

      expect(job.recipients.length, equals(3));
      expect(job.envelopeIds.length, equals(3));
      expect(job.status, equals(BulkSendStatus.draft));
    });

    test('generates envelopes from bulk job', () {
      const template = EnvelopeTemplate(
        id: 'tmpl-gen',
        name: 'Test',
        subject: 'Test',
        roles: [
          TemplateRole(
            roleId: 'x',
            roleName: 'X',
            recipientRole: RecipientRole.signer,
          ),
        ],
        fields: [],
      );

      final recipients = [
        const BulkRecipient(name: 'A', email: 'a@t.com'),
        const BulkRecipient(name: 'B', email: 'b@t.com'),
      ];

      final job = BulkSendJob.fromTemplate(
        jobId: 'bulk-gen',
        template: template,
        signerRoleId: 'x',
        recipients: recipients,
        documentMerkleRoots: ['doc'],
      );

      final envelopes = job.createEnvelopes(
        template: template,
        signerRoleId: 'x',
        documentMerkleRoots: ['doc'],
      );

      expect(envelopes.length, equals(2));
      expect(envelopes[0].recipients[0].name, equals('A'));
      expect(envelopes[1].recipients[0].name, equals('B'));
      // Each envelope should have unique ID.
      expect(envelopes[0].id, isNot(equals(envelopes[1].id)));
    });

    test('rejects job with invalid signer role', () {
      const template = EnvelopeTemplate(
        id: 'tmpl-invalid',
        name: 'Test',
        subject: 'Test',
        roles: [
          TemplateRole(
            roleId: 'real',
            roleName: 'Real',
            recipientRole: RecipientRole.signer,
          ),
        ],
        fields: [],
      );

      expect(
        () => BulkSendJob.fromTemplate(
          jobId: 'bad',
          template: template,
          signerRoleId: 'nonexistent',
          recipients: const [
            BulkRecipient(name: 'X', email: 'x@t.com'),
          ],
          documentMerkleRoots: [],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

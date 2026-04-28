import re

with open('lib/lib/src/crypto_glossary.dart', 'r') as f:
    content = f.read()

glossary_addition = """    'post-quantum-cryptography': const GlossaryTerm(
      term: 'post-quantum-cryptography',
      title: 'Post-Quantum Cryptography (PQC)',
      tooltip: 'Cryptographic algorithms resistant to quantum computer attacks.',
      description:
          'PQC refers to new mathematical algorithms designed to be secure against '
          'the massive computing power of future quantum computers. Zegel employs '
          'PQC (like Kyber/ML-KEM and Dilithium/ML-DSA) alongside traditional cryptography '
          'to ensure long-term data security against "store now, decrypt later" attacks.',
      seeAlso: <String>['aes-256-gcm', 'ed25519'],
    ),
  };"""

if "post-quantum-cryptography" not in content:
    content = content.replace("  };", glossary_addition)
    content = content.replace("'ed25519'],", "'ed25519', 'post-quantum-cryptography'],")

with open('lib/lib/src/crypto_glossary.dart', 'w') as f:
    f.write(content)

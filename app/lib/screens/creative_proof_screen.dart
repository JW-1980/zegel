import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';
import '../widgets/key_input.dart';
import 'creative_viewer_screen.dart';

/// Screen for sealing creative works with proof-of-origination.
///
/// Captures creator identity, optional ID document scans, work metadata,
/// and seals the creative asset into a tamper-proof .zgl container with
/// an Ed25519 signature binding content to creator.
class CreativeProofScreen extends StatefulWidget {
  final String? initialFilePath;

  const CreativeProofScreen({super.key, this.initialFilePath});

  @override
  State<CreativeProofScreen> createState() => _CreativeProofScreenState();
}

class _CreativeProofScreenState extends State<CreativeProofScreen> {
  // File state
  String? _filePath;
  String? _fileName;
  int? _fileSize;
  String _hexKey = '';
  bool _isSealing = false;
  String? _statusMessage;
  bool _isError = false;

  // Creator identity
  final _firstNameCtrl = TextEditingController();
  final _familyNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _zipCodeCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _companyRegCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();

  // Work metadata
  final _workTitleCtrl = TextEditingController();
  final _workDescCtrl = TextEditingController();
  CreativeWorkType _workType = CreativeWorkType.other;
  final List<String> _tags = [];
  final _tagCtrl = TextEditingController();

  // ID documents
  final List<_IdDocEntry> _idDocs = [];

  // Options
  bool _compress = false;
  bool _privateIdentity = false;

  // Signing key
  String? _signingKeyPath;
  String? _signingKeyName;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _setFile(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _firstNameCtrl, _familyNameCtrl, _middleNameCtrl, _dobCtrl,
      _addressCtrl, _zipCodeCtrl, _cityCtrl, _stateCtrl, _countryCtrl,
      _companyCtrl, _companyRegCtrl, _emailCtrl, _phoneCtrl, _websiteCtrl,
      _titleCtrl, _workTitleCtrl, _workDescCtrl, _tagCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _setFile(String path) async {
    final fileService = context.read<FileService>();
    final size = await fileService.getFileSize(path);
    final name = fileService.getFileName(path);
    final mime = CreativeProof.guessMimeType(name);

    setState(() {
      _filePath = path;
      _fileSize = size;
      _fileName = name;
      _workType = CreativeProof.guessWorkType(mime);
      _statusMessage = null;
      _isError = false;
    });
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) await _setFile(path);
  }

  Future<void> _pickSigningKey() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      setState(() {
        _signingKeyPath = path;
        _signingKeyName = fileService.getFileName(path);
      });
    }
  }

  Future<void> _pickIdDocScan() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      setState(() {
        _idDocs.add(_IdDocEntry(
          path: path,
          fileName: fileService.getFileName(path),
          type: IdDocumentType.passport,
        ));
      });
    }
  }

  void _removeIdDoc(int index) {
    setState(() => _idDocs.removeAt(index));
  }

  void _addTag() {
    final tag = _tagCtrl.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagCtrl.clear();
      });
    }
  }

  void _removeTag(int index) {
    setState(() => _tags.removeAt(index));
  }

  Future<void> _seal() async {
    // Validate required fields.
    if (_filePath == null) {
      _setError('Select a creative asset file.');
      return;
    }
    if (_hexKey.length != 64) {
      _setError('Enter a valid 64-character hex master key.');
      return;
    }
    if (_firstNameCtrl.text.trim().isEmpty) {
      _setError('Creator first name is required.');
      return;
    }
    if (_familyNameCtrl.text.trim().isEmpty) {
      _setError('Creator family name is required.');
      return;
    }
    if (_signingKeyPath == null) {
      _setError('Select an Ed25519 signing key file.');
      return;
    }

    setState(() {
      _isSealing = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final fileService = context.read<FileService>();

      // Read content.
      final content = await fileService.readFileBytes(_filePath!);
      final mime = CreativeProof.guessMimeType(_fileName!);

      // Read signing key.
      final signingKeyBytes = await fileService.readFileBytes(_signingKeyPath!);
      Uint8List signingKey;
      if (signingKeyBytes.length == 32) {
        signingKey = signingKeyBytes;
      } else {
        final text = String.fromCharCodes(signingKeyBytes).trim();
        if (text.length == 64 &&
            RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) {
          signingKey = _hexToBytes(text);
        } else {
          _setError('Signing key must be 32 raw bytes or 64 hex characters.');
          return;
        }
      }

      final masterKey = _hexToBytes(_hexKey);

      // Build creator identity.
      final creator = CreatorIdentity(
        firstName: _firstNameCtrl.text.trim(),
        familyName: _familyNameCtrl.text.trim(),
        middleName: _nullIfEmpty(_middleNameCtrl.text),
        dateOfBirth: _nullIfEmpty(_dobCtrl.text),
        address: _nullIfEmpty(_addressCtrl.text),
        zipCode: _nullIfEmpty(_zipCodeCtrl.text),
        city: _nullIfEmpty(_cityCtrl.text),
        stateProvince: _nullIfEmpty(_stateCtrl.text),
        country: _nullIfEmpty(_countryCtrl.text),
        companyName: _nullIfEmpty(_companyCtrl.text),
        companyRegistrationNumber: _nullIfEmpty(_companyRegCtrl.text),
        email: _nullIfEmpty(_emailCtrl.text),
        phone: _nullIfEmpty(_phoneCtrl.text),
        website: _nullIfEmpty(_websiteCtrl.text),
        professionalTitle: _nullIfEmpty(_titleCtrl.text),
      );

      // Load ID document scans.
      final List<IdDocument> idDocuments = [];
      for (final entry in _idDocs) {
        final scanBytes = await fileService.readFileBytes(entry.path);
        final scanMime = CreativeProof.guessMimeType(entry.fileName);
        idDocuments.add(IdDocument(
          type: entry.type,
          scanBytes: scanBytes,
          scanMimeType: scanMime,
          issuingCountry: _nullIfEmpty(_countryCtrl.text),
          holderName: creator.displayName,
        ));
      }

      final options = CreativeProofOptions(
        workType: _workType,
        workTitle: _nullIfEmpty(_workTitleCtrl.text),
        workDescription: _nullIfEmpty(_workDescCtrl.text),
        tags: _tags.isNotEmpty ? List<String>.from(_tags) : null,
        compress: _compress,
        includeIdentityInPublicMetadata: !_privateIdentity,
      );

      final sealed = CreativeProof.seal(
        content: content,
        contentType: mime,
        filename: _fileName!,
        masterKey: masterKey,
        creatorSigningKey: signingKey,
        creator: creator,
        options: options,
        idDocuments: idDocuments.isNotEmpty ? idDocuments : null,
      );

      final suggestedName = '${_fileName!}.zgl';
      final savedPath = await fileService.saveFile(sealed, suggestedName);

      if (savedPath != null && mounted) {
        setState(() {
          _statusMessage =
              'Creative proof sealed! ${creator.displayName}\'s work '
              '"${options.workTitle ?? _fileName}" saved to $savedPath';
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) _setError('Error: $e');
    } finally {
      if (mounted) setState(() => _isSealing = false);
    }
  }

  void _setError(String msg) {
    setState(() {
      _statusMessage = msg;
      _isError = true;
      _isSealing = false;
    });
  }

  String? _nullIfEmpty(String s) {
    final trimmed = s.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Uint8List _hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Creative Proof'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            tooltip: 'Verify & View',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CreativeViewerScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Creative asset file picker ---
            _buildSectionHeader(theme, Icons.music_note, 'CREATIVE ASSET'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _isSealing ? null : _pickFile,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _workTypeIcon(_workType),
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _filePath != null
                          ? _fileName ?? 'File selected'
                          : 'SELECT YOUR CREATIVE WORK',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_filePath != null && _fileSize != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${fileService.formatFileSize(_fileSize!)} - ${_workType.name.toUpperCase()}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_filePath == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Music, images, video, documents, photos...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Work metadata ---
            _buildSectionHeader(theme, Icons.info_outline, 'WORK DETAILS'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _workTitleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Work Title',
                        hintText: 'e.g. "Midnight Sonata"',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _workDescCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Brief description of the work',
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<CreativeWorkType>(
                      value: _workType,
                      decoration: const InputDecoration(
                        labelText: 'Work Type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: CreativeWorkType.values.map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Row(
                            children: [
                              Icon(_workTypeIcon(t), size: 18),
                              const SizedBox(width: 8),
                              Text(t.name[0].toUpperCase() +
                                  t.name.substring(1)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _isSealing
                          ? null
                          : (v) => setState(() => _workType = v!),
                    ),
                    const SizedBox(height: 12),
                    // Tags
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Tags',
                              hintText: 'Add a tag',
                              isDense: true,
                            ),
                            onSubmitted: (_) => _addTag(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle),
                          onPressed: _addTag,
                        ),
                      ],
                    ),
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _tags.asMap().entries.map((e) {
                            return Chip(
                              label: Text(e.value),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => _removeTag(e.key),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Creator identity ---
            _buildSectionHeader(theme, Icons.person, 'CREATOR IDENTITY'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _firstNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'First Name *',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _middleNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Middle Name',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _familyNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Family Name *',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dobCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Date of Birth',
                              hintText: 'YYYY-MM-DD',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _titleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Professional Title',
                              hintText: 'e.g. Composer',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    TextField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _zipCodeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Zip Code',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _cityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'City',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stateCtrl,
                            decoration: const InputDecoration(
                              labelText: 'State/Province',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _countryCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Country',
                              hintText: 'e.g. NL',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _companyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Company Name',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _companyRegCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Registration No.',
                              hintText: 'e.g. KvK number',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _phoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _websiteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Website',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- ID Documents ---
            _buildSectionHeader(
                theme, Icons.badge, 'IDENTITY DOCUMENTS (optional)'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_idDocs.isEmpty)
                      Text(
                        'Attach scans of passport, ID card, or driver license\n'
                        'to strengthen proof of identity.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ..._idDocs.asMap().entries.map((e) {
                      final idx = e.key;
                      final doc = e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.description, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                doc.fileName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<IdDocumentType>(
                              value: doc.type,
                              isDense: true,
                              items: IdDocumentType.values.map((t) {
                                return DropdownMenuItem(
                                  value: t,
                                  child: Text(_idDocTypeLabel(t)),
                                );
                              }).toList(),
                              onChanged: (v) {
                                setState(() => _idDocs[idx].type = v!);
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.remove_circle,
                                  color: theme.colorScheme.error),
                              onPressed: () => _removeIdDoc(idx),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isSealing ? null : _pickIdDocScan,
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('ADD ID DOCUMENT SCAN'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Signing key ---
            _buildSectionHeader(theme, Icons.vpn_key, 'SIGNING KEY'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ed25519 private key for cryptographic proof of authorship.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _signingKeyPath != null
                                ? _signingKeyName ?? 'Key selected'
                                : 'No signing key selected',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSealing ? null : _pickSigningKey,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('SELECT KEY'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Master key ---
            _buildSectionHeader(theme, Icons.lock, 'MASTER KEY'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: KeyInput(
                  onKeyChanged: (key) => setState(() => _hexKey = key),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- Options ---
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Compress content'),
                    subtitle: const Text('zlib compression before encryption'),
                    value: _compress,
                    onChanged: _isSealing
                        ? null
                        : (v) => setState(() => _compress = v),
                  ),
                  SwitchListTile(
                    title: const Text('Private identity'),
                    subtitle: const Text(
                      'Hide creator name from public metadata '
                      '(visible only with master key)',
                    ),
                    value: _privateIdentity,
                    onChanged: _isSealing
                        ? null
                        : (v) => setState(() => _privateIdentity = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- Status ---
            if (_statusMessage != null)
              _buildStatusBanner(theme),

            const SizedBox(height: 16),

            // --- Seal button ---
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _isSealing ? null : _seal,
                icon: _isSealing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.verified, size: 28),
                label: Text(
                  _isSealing
                      ? 'SEALING CREATIVE PROOF...'
                      : 'SEAL CREATIVE PROOF',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isError
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _isError
              ? Colors.red.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isError ? Icons.error : Icons.check_circle,
            color: _isError ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(
                color: _isError ? Colors.red.shade900 : Colors.green.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _workTypeIcon(CreativeWorkType type) {
    switch (type) {
      case CreativeWorkType.music:
        return Icons.music_note;
      case CreativeWorkType.image:
        return Icons.image;
      case CreativeWorkType.video:
        return Icons.videocam;
      case CreativeWorkType.photo:
        return Icons.photo_camera;
      case CreativeWorkType.document:
        return Icons.description;
      case CreativeWorkType.software:
        return Icons.code;
      case CreativeWorkType.design:
        return Icons.palette;
      case CreativeWorkType.animation:
        return Icons.animation;
      case CreativeWorkType.poem:
        return Icons.auto_stories;
      case CreativeWorkType.screenplay:
        return Icons.movie_creation;
      case CreativeWorkType.other:
        return Icons.star;
    }
  }

  String _idDocTypeLabel(IdDocumentType type) {
    switch (type) {
      case IdDocumentType.passport:
        return 'Passport';
      case IdDocumentType.identityCard:
        return 'ID Card';
      case IdDocumentType.driverLicense:
        return 'Driver License';
      case IdDocumentType.residencePermit:
        return 'Residence Permit';
      case IdDocumentType.other:
        return 'Other';
    }
  }
}

class _IdDocEntry {
  final String path;
  final String fileName;
  IdDocumentType type;

  _IdDocEntry({
    required this.path,
    required this.fileName,
    required this.type,
  });
}

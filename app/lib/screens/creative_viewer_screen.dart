import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';
import '../widgets/key_input.dart';

/// Screen for verifying and viewing/playing creative proof containers.
///
/// After verification, renders the content inline based on its MIME type:
/// - Images (PNG, JPEG, GIF, WebP, BMP) are displayed directly
/// - Text and source files are shown in a scrollable view
/// - Audio and video display metadata with an export-to-play option
/// - Other files show metadata and an extract button
///
/// Also displays full creator identity, Ed25519 signature status,
/// work metadata, and ID document information.
class CreativeViewerScreen extends StatefulWidget {
  final String? initialFilePath;

  const CreativeViewerScreen({super.key, this.initialFilePath});

  @override
  State<CreativeViewerScreen> createState() => _CreativeViewerScreenState();
}

class _CreativeViewerScreenState extends State<CreativeViewerScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isVerifying = false;
  String? _errorMessage;

  // Results
  CreativeProofResult? _result;
  CreativeProofInspection? _inspection;
  bool? _publicSigValid;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _filePath = widget.initialFilePath;
    }
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _result = null;
        _inspection = null;
        _publicSigValid = null;
        _errorMessage = null;
      });
      _inspectFile(path);
    }
  }

  Future<void> _inspectFile(String path) async {
    try {
      final fileService = context.read<FileService>();
      final fileBytes = await fileService.readFileBytes(path);
      final insp = CreativeProof.inspect(fileBytes);
      final sigValid = CreativeProof.verifyPublicSignature(fileBytes);
      if (mounted) {
        setState(() {
          _inspection = insp;
          _publicSigValid = sigValid;
        });
      }
    } catch (_) {
      // Inspection is optional; user can still verify with key.
    }
  }

  Future<void> _verify() async {
    if (_filePath == null) {
      setState(() => _errorMessage = 'Select a .zgl file first.');
      return;
    }
    if (_hexKey.length != 64) {
      setState(
          () => _errorMessage = 'Enter a valid 64-character hex master key.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _result = null;
      _errorMessage = null;
    });

    try {
      final fileService = context.read<FileService>();
      final fileBytes = await fileService.readFileBytes(_filePath!);
      final masterKey = _hexToBytes(_hexKey);
      final result = CreativeProof.verify(fileBytes, masterKey);

      if (mounted) {
        setState(() {
          _result = result;
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Verification failed: $e';
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _extractContent() async {
    if (_result?.content == null) return;
    final fileService = context.read<FileService>();
    final suggestedName = _result!.originalFilename ?? 'extracted_content';
    final savedPath = await fileService.saveFile(
      _result!.content!,
      suggestedName,
    );
    if (savedPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Extracted to: $savedPath')),
      );
    }
  }

  Future<void> _extractIdDoc(IdDocument doc, int index) async {
    final fileService = context.read<FileService>();
    final ext = doc.scanMimeType.split('/').last;
    final name = 'id_doc_${index + 1}_${doc.type.name}.$ext';
    final savedPath = await fileService.saveFile(doc.scanBytes, name);
    if (savedPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ID document saved to: $savedPath')),
      );
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Creative Proof Viewer'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File picker
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.verified, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Creative Proof File',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filePath != null) ...[
                      Text(
                        context.read<FileService>().getFileName(_filePath!),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ] else
                      Text(
                        'No file selected',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isVerifying ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select .zgl File'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Public inspection (no key needed)
            if (_inspection != null && _inspection!.isCreativeProof)
              _buildPublicInspection(theme),

            if (_inspection != null && !_inspection!.isCreativeProof)
              _buildNotCreativeProofBanner(theme),

            const SizedBox(height: 12),

            // Key input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: KeyInput(
                  onKeyChanged: (key) => setState(() => _hexKey = key),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Verify button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isVerifying ? null : _verify,
                icon: _isVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.verified_user),
                label: Text(
                  _isVerifying ? 'VERIFYING...' : 'VERIFY & VIEW',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Error message
            if (_errorMessage != null)
              _buildBanner(theme, _errorMessage!, true),

            // Full results
            if (_result != null) ...[
              _buildVerificationStatus(theme),
              const SizedBox(height: 12),
              _buildCreatorCard(theme),
              const SizedBox(height: 12),
              _buildCryptoProofCard(theme),
              const SizedBox(height: 12),
              _buildWorkDetailsCard(theme),
              const SizedBox(height: 12),
              _buildContentPreview(theme),
              if (_result!.idDocuments != null &&
                  _result!.idDocuments!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildIdDocumentsCard(theme),
              ],
              const SizedBox(height: 12),
              // Extract button
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _result!.content != null ? _extractContent : null,
                  icon: const Icon(Icons.file_download),
                  label: Text(
                    'EXTRACT ORIGINAL ${_result!.workType?.name.toUpperCase() ?? "FILE"}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ---------- Public inspection (no key) ----------

  Widget _buildPublicInspection(ThemeData theme) {
    final insp = _inspection!;
    final dateStr = insp.createdAt != null
        ? DateFormat('yyyy-MM-dd HH:mm:ss').format(insp.createdAt!.toLocal())
        : 'Unknown';

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified,
                    color: _publicSigValid == true
                        ? Colors.green
                        : Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Creative Proof Detected',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _publicSigValid == true
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _publicSigValid == true
                        ? 'SIGNATURE VALID'
                        : 'SIGNATURE UNVERIFIED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _publicSigValid == true
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow('Creator', insp.creatorName ?? 'Hidden'),
            if (insp.workTitle != null)
              _infoRow('Title', insp.workTitle!),
            _infoRow('Type', insp.workType ?? 'Unknown'),
            _infoRow('Created', dateStr),
            _infoRow('MIME', insp.contentType ?? 'Unknown'),
            if (insp.tags != null && insp.tags!.isNotEmpty)
              _infoRow('Tags', insp.tags!.join(', ')),
            const SizedBox(height: 8),
            Text(
              'Enter the master key below to verify content and view/play.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotCreativeProofBanner(ThemeData theme) {
    return _buildBanner(
      theme,
      'This is a standard Zegel file, not a creative proof container.',
      false,
    );
  }

  // ---------- Post-verification widgets ----------

  Widget _buildVerificationStatus(ThemeData theme) {
    final valid = _result!.valid;
    final sigValid = _result!.signatureValid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: valid && sigValid
            ? Colors.green.withValues(alpha: 0.1)
            : valid
                ? Colors.orange.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: valid && sigValid
              ? Colors.green.withValues(alpha: 0.3)
              : valid
                  ? Colors.orange.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            valid && sigValid
                ? Icons.verified
                : valid
                    ? Icons.warning
                    : Icons.error,
            size: 40,
            color: valid && sigValid
                ? Colors.green
                : valid
                    ? Colors.orange
                    : Colors.red,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valid && sigValid
                      ? 'VERIFIED CREATIVE PROOF'
                      : valid
                          ? 'CONTENT VALID, SIGNATURE ISSUE'
                          : 'VERIFICATION FAILED',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valid && sigValid
                        ? Colors.green.shade800
                        : valid
                            ? Colors.orange.shade800
                            : Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valid && sigValid
                      ? 'Content is intact and cryptographically bound to the creator.'
                      : valid
                          ? 'Content is intact but the creator signature could not be verified.'
                          : 'Content has been tampered with or key is wrong.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorCard(ThemeData theme) {
    final c = _result!.creator;
    if (c == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, Icons.person, 'Creator Identity'),
            const SizedBox(height: 12),
            _infoRow('Name', c.displayName),
            if (c.professionalTitle != null)
              _infoRow('Title', c.professionalTitle!),
            if (c.dateOfBirth != null)
              _infoRow('Born', c.dateOfBirth!),
            if (c.address != null) _infoRow('Address', c.address!),
            if (c.zipCode != null || c.city != null)
              _infoRow('Location',
                  [c.zipCode, c.city].where((s) => s != null).join(' ')),
            if (c.stateProvince != null)
              _infoRow('State', c.stateProvince!),
            if (c.country != null) _infoRow('Country', c.country!),
            if (c.companyName != null)
              _infoRow('Company', c.companyName!),
            if (c.companyRegistrationNumber != null)
              _infoRow('Reg. No.', c.companyRegistrationNumber!),
            if (c.email != null) _infoRow('Email', c.email!),
            if (c.phone != null) _infoRow('Phone', c.phone!),
            if (c.website != null) _infoRow('Website', c.website!),
            _infoRow('Fingerprint', c.fingerprint),
          ],
        ),
      ),
    );
  }

  Widget _buildCryptoProofCard(ThemeData theme) {
    final dateStr = _result!.createdAt != null
        ? DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(_result!.createdAt!.toLocal())
        : 'Unknown';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, Icons.fingerprint, 'Cryptographic Proof'),
            const SizedBox(height: 12),
            _infoRow(
              'Signature',
              _result!.signatureValid ? 'VALID' : 'INVALID',
              valueColor:
                  _result!.signatureValid ? Colors.green : Colors.red,
            ),
            _infoRow('Created', dateStr),
            _infoRow('Content Hash', _result!.contentHashHex ?? 'N/A',
                monospace: true),
            _infoRow('Public Key', _result!.creatorPublicKeyHex ?? 'N/A',
                monospace: true),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkDetailsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(
              theme,
              _workTypeIcon(_result!.workType ?? CreativeWorkType.other),
              'Work Details',
            ),
            const SizedBox(height: 12),
            _infoRow('Type', _result!.workType?.name ?? 'Unknown'),
            if (_result!.workTitle != null)
              _infoRow('Title', _result!.workTitle!),
            if (_result!.workDescription != null)
              _infoRow('Description', _result!.workDescription!),
            _infoRow('MIME', _result!.contentType ?? 'Unknown'),
            _infoRow('Filename', _result!.originalFilename ?? 'Unknown'),
            if (_result!.content != null)
              _infoRow('Size', _formatFileSize(_result!.content!.length)),
            if (_result!.tags != null && _result!.tags!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _result!.tags!.map((t) {
                    return Chip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentPreview(ThemeData theme) {
    if (_result?.content == null || _result!.contentType == null) {
      return const SizedBox.shrink();
    }

    final mime = _result!.contentType!;
    final content = _result!.content!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, Icons.preview, 'Content Preview'),
            const SizedBox(height: 12),
            if (_isImageMime(mime))
              _buildImagePreview(content, theme)
            else if (_isTextMime(mime))
              _buildTextPreview(content, theme)
            else if (_isAudioMime(mime))
              _buildAudioInfo(theme)
            else if (_isVideoMime(mime))
              _buildVideoInfo(theme)
            else
              _buildGenericInfo(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(Uint8List bytes, ThemeData theme) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return Container(
                height: 200,
                color: theme.colorScheme.surfaceContainerLow,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      const Text('Unable to render image preview'),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_result!.originalFilename} - ${_formatFileSize(bytes.length)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildTextPreview(Uint8List bytes, ThemeData theme) {
    String text;
    try {
      text = String.fromCharCodes(bytes);
    } catch (_) {
      text = '(Binary content cannot be displayed as text)';
    }

    final previewText =
        text.length > 5000 ? '${text.substring(0, 5000)}\n\n... (truncated)' : text;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          previewText,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(Icons.music_note,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            _result!.workTitle ?? _result!.originalFilename ?? 'Audio file',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_result!.contentType} - ${_formatFileSize(_result!.content!.length)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Extract the file to play it in your preferred audio player.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(Icons.videocam,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            _result!.workTitle ?? _result!.originalFilename ?? 'Video file',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_result!.contentType} - ${_formatFileSize(_result!.content!.length)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Extract the file to play it in your preferred video player.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(Icons.description,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            _result!.originalFilename ?? 'File',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${_result!.contentType} - ${_formatFileSize(_result!.content!.length)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdDocumentsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(theme, Icons.badge, 'Identity Documents'),
            const SizedBox(height: 12),
            ...List.generate(_result!.idDocuments!.length, (i) {
              final doc = _result!.idDocuments![i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.badge,
                              size: 20,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            _idDocTypeLabel(doc.type),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _extractIdDoc(doc, i),
                            icon: const Icon(Icons.save_alt, size: 16),
                            label: const Text('Save'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _infoRow('Format', doc.scanMimeType),
                      _infoRow(
                          'Size', _formatFileSize(doc.scanBytes.length)),
                      if (doc.issuingCountry != null)
                        _infoRow('Country', doc.issuingCountry!),
                      if (doc.holderName != null)
                        _infoRow('Holder', doc.holderName!),
                      // Show image preview for image scans.
                      if (_isImageMime(doc.scanMimeType)) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: Image.memory(
                              doc.scanBytes,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Text('Preview unavailable'),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------- Helpers ----------

  Widget _sectionTitle(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value,
      {Color? valueColor, bool monospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(ThemeData theme, String message, bool isError) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? Colors.red.withValues(alpha: 0.1)
              : Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isError
                ? Colors.red.withValues(alpha: 0.3)
                : Colors.orange.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.info,
              color: isError ? Colors.red : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  bool _isImageMime(String mime) {
    return mime.startsWith('image/') &&
        !mime.contains('svg') &&
        !mime.contains('photoshop');
  }

  bool _isTextMime(String mime) {
    return mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml';
  }

  bool _isAudioMime(String mime) => mime.startsWith('audio/');
  bool _isVideoMime(String mime) => mime.startsWith('video/');

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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';

/// Screen for capturing handwritten (wet) signatures.
///
/// Provides a drawing canvas where users can sign with their finger (touch),
/// mouse, or stylus. Also captures signer name, city (woonplaats), and date.
///
/// Configurable for multi-party signing: a setting determines how many people
/// must sign before the document is considered complete.
class WetSignatureScreen extends StatefulWidget {
  /// Optional initial file path.
  final String? initialFilePath;

  const WetSignatureScreen({super.key, this.initialFilePath});

  @override
  State<WetSignatureScreen> createState() => _WetSignatureScreenState();
}

class _WetSignatureScreenState extends State<WetSignatureScreen> {
  String? _filePath;

  bool _isLoading = false;
  String? _statusMessage;
  bool _isError = false;

  // Signature fields.
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();
  int _requiredSignatures = 1;

  // Drawing state.
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  bool _hasSigned = false;

  // Existing signatures on the file.
  final List<WetSignature> _existingSignatures = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _setFile(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _setFile(String path) async {
    setState(() {
      _filePath = path;
      _statusMessage = null;
      _isError = false;
    });
  }

  Future<void> _pickFile() async {
    final path = await context.read<FileService>().pickFile();
    if (path != null) {
      _setFile(path);
    }
  }

  void _clearSignature() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _hasSigned = false;
    });
  }

  Future<Uint8List> _exportSignatureAsPng() async {
    // Render strokes to an image.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(400, 200);

    // White background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // Draw strokes.
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw StateError('Failed to export signature as PNG');
    }

    return byteData.buffer.asUint8List();
  }

  Future<void> _submitSignature() async {
    if (_filePath == null) {
      setState(() {
        _statusMessage = 'Please select a .zgl file first.';
        _isError = true;
      });
      return;
    }

    if (!_hasSigned || _strokes.isEmpty) {
      setState(() {
        _statusMessage = 'Please draw your signature on the pad.';
        _isError = true;
      });
      return;
    }

    final name = _nameController.text.trim();
    final city = _cityController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter your name.';
        _isError = true;
      });
      return;
    }

    if (city.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter your woonplaats (city).';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final signatureImage = await _exportSignatureAsPng();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final role = _roleController.text.trim();

      final signature = WetSignature(
        signatureImage: signatureImage,
        signerName: name,
        signerCity: city,
        signedAt: now,
        signerRole: role.isNotEmpty ? role : null,
      );

      // Encode the signature and save it as a sidecar file.
      final encoded = signature.encode();

      // Save the signature data alongside the .zgl file.
      if (_filePath != null) {
        final sigPath = '${_filePath!}.sig-$name.json';
        final sigJson = {
          'type': 'wet_signature',
          'signer_name': name,
          'signer_city': city,
          'signer_role': role.isNotEmpty ? role : null,
          'signed_at': now,
          'signature_size_bytes': signatureImage.length,
          'encoding': 'base64_png',
          'data_base64': base64Encode(signatureImage),
        };
        await File(
          sigPath,
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(sigJson));

        setState(() {
          _statusMessage = 'Signature saved to ${sigPath.split('/').last}\n'
              'Signed by $name from $city on '
              '${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}.\n'
              '(${encoded.length} bytes encoded)';
          _isError = false;
          _existingSignatures.add(signature);
        });
      } else {
        setState(() {
          _statusMessage = 'Signature captured (${encoded.length} bytes). '
              'No file selected — signature not saved to disk.';
          _isError = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isError = true;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wet Signature'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear signature',
            onPressed: _clearSignature,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File selection.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_filePath != null)
                      Text(
                        _filePath!,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.file_open),
                      label: const Text('Select .zgl file'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Signature pad.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Draw Your Signature',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: GestureDetector(
                        onPanStart: (details) {
                          setState(() {
                            _currentStroke = [details.localPosition];
                            _hasSigned = true;
                          });
                        },
                        onPanUpdate: (details) {
                          setState(() {
                            _currentStroke.add(details.localPosition);
                          });
                        },
                        onPanEnd: (details) {
                          setState(() {
                            _strokes.add(List.from(_currentStroke));
                            _currentStroke = [];
                          });
                        },
                        child: CustomPaint(
                          painter: _SignaturePainter(
                            strokes: _strokes,
                            currentStroke: _currentStroke,
                          ),
                          size: const Size(double.infinity, 200),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use your finger, stylus, or mouse to sign above',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Signer information.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signer Information',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        hintText: 'Enter your full legal name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'Woonplaats (City) *',
                        hintText: 'Enter your city of residence',
                        prefixIcon: Icon(Icons.location_city),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _roleController,
                      decoration: const InputDecoration(
                        labelText: 'Role (optional)',
                        hintText: 'e.g. Buyer, Seller, Witness, Notary',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Date: ${DateFormat('dd MMMM yyyy').format(DateTime.now())}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Multi-party signing configuration.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signing Requirements',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Required signatures: '),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _requiredSignatures,
                          items: List.generate(
                            10,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}'),
                            ),
                          ),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _requiredSignatures = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Submit button.
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _submitSignature,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.draw),
              label: Text(_isLoading ? 'Signing...' : 'Apply Signature'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            // Status message.
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isError ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        _isError ? Colors.red.shade200 : Colors.green.shade200,
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
                          color: _isError
                              ? Colors.red.shade900
                              : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Existing signatures.
            if (_existingSignatures.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Existing Signatures',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ..._existingSignatures.map(
                (sig) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.draw, color: Colors.blue),
                    title: Text(sig.signerName),
                    subtitle: Text(
                      '${sig.signerCity} - ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(sig.signedAt * 1000))}'
                      '${sig.signerRole != null ? ' (${sig.signerRole})' : ''}',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the signature canvas.
class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes, required this.currentStroke});

  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw completed strokes.
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, paint);
    }

    // Draw current (in-progress) stroke.
    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke, paint);
    }

    // Draw baseline.
    final baselinePaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(20, size.height * 0.75),
      Offset(size.width - 20, size.height * 0.75),
      baselinePaint,
    );
  }

  void _drawStroke(Canvas canvas, List<Offset> stroke, Paint paint) {
    if (stroke.length < 2) return;
    final path = Path();
    path.moveTo(stroke.first.dx, stroke.first.dy);
    for (int i = 1; i < stroke.length; i++) {
      // Smooth with quadratic bezier for natural look.
      if (i < stroke.length - 1) {
        final mid = Offset(
          (stroke[i].dx + stroke[i + 1].dx) / 2,
          (stroke[i].dy + stroke[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(stroke[i].dx, stroke[i].dy, mid.dx, mid.dy);
      } else {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return true; // Repaint on every stroke update.
  }
}

with open("app/lib/services/zegel_service.dart", "r") as f:
    content = f.read()

search = """    // Delegate to the zegel library.
    // The actual implementation calls into package:zegel.
    // For now, this is a placeholder that returns empty bytes
    // until the core library is fully integrated.
    throw UnimplementedError(
      'Seal operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );"""

replace = """    final Uint8List masterKey = _hexToBytes(hexKey);
    final String filename = file.uri.pathSegments.last;
    final Uint8List content = await file.readAsBytes();

    final zegelOptions = ZegelOptions(
      filename: filename,
      compress: options.compress,
      expiration: options.expirationDate,
      recipientId: options.recipientId != null ? _hexToBytes(options.recipientId!) : null,
      splitKeyThreshold: options.splitKeyThreshold,
      splitKeyTotal: options.splitKeyTotal,
      enableSelectiveDisclosure: options.enableSelectiveDisclosure,
      metadata: options.metadata,
      blockSize: options.blockSize,
    );

    final writer = ZegelWriter(masterKey, zegelOptions);
    return writer.seal(content);"""

new_content = content.replace(search, replace)
if new_content != content:
    with open("app/lib/services/zegel_service.dart", "w") as f:
        f.write(new_content)
    print("Patched seal method")
else:
    print("Failed to patch seal method")

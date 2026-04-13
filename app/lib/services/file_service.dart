import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'dart:io';

/// Service for picking and saving files using platform dialogs.
class FileService {
  /// Picks any file from the file system.
  ///
  /// Returns the file path, or null if the user cancelled.
  Future<String?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      return result.files.single.path;
    }
    return null;
  }

  /// Picks a .zgl file from the file system.
  ///
  /// Returns the file path, or null if the user cancelled.
  Future<String?> pickZegelFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      return result.files.single.path;
    }
    return null;
  }

  /// Saves bytes to a file, showing a save dialog with the suggested name.
  ///
  /// Returns the saved file path, or null if the user cancelled.
  Future<String?> saveFile(Uint8List bytes, String suggestedName) async {
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save file',
      fileName: suggestedName,
    );
    if (outputPath != null) {
      final file = File(outputPath);
      await file.writeAsBytes(bytes);
      return outputPath;
    }
    return null;
  }

  /// Reads all bytes from a file at the given path.
  Future<Uint8List> readFileBytes(String path) async {
    final file = File(path);
    return file.readAsBytes();
  }

  /// Returns the file size in bytes.
  Future<int> getFileSize(String path) async {
    final file = File(path);
    return file.length();
  }

  /// Returns the filename from a path.
  String getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  /// Returns the file extension (lowercase, without dot).
  String getFileExtension(String path) {
    final name = getFileName(path);
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }

  /// Returns true if the file has a .zgl extension.
  bool isZegelFile(String path) {
    return getFileExtension(path) == 'zgl';
  }

  /// Formats a byte size into a human-readable string.
  String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Picks a directory from the file system.
  ///
  /// Returns the directory path, or null if the user cancelled.
  Future<String?> pickDirectory() async {
    return FilePicker.getDirectoryPath(dialogTitle: 'Select folder');
  }

  /// Lists all .zgl files in a directory.
  Future<List<String>> listZegelFiles(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];
    return dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.zgl'))
        .map((entity) => entity.path)
        .toList();
  }

  /// Lists all regular files in a directory (non-recursive).
  Future<List<String>> listAllFiles(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];
    return dir
        .list()
        .where((entity) => entity is File)
        .map((entity) => entity.path)
        .toList();
  }

  /// Saves bytes to a specific file path (no dialog).
  Future<void> saveFileToPath(Uint8List bytes, String outputPath) async {
    final file = File(outputPath);
    await file.writeAsBytes(bytes);
  }
}

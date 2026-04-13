import 'dart:io';
import 'dart:typed_data';

/// Chunked random-access file reader for large `.zgl` files
/// (improvement #63).
///
/// Dart does not expose true `mmap(2)` without FFI, but a
/// [RandomAccessFile] backed reader gives us most of the benefits:
/// the OS page cache kicks in automatically for repeated reads, we
/// avoid loading the entire file into the Dart heap, and we can
/// random-access blocks by byte offset.
///
/// The reader is safe to share across one isolate — callers should
/// not hand the same instance to multiple concurrent consumers.
/// Close the reader with [close] when done.
class MmapReader {
  MmapReader._(this._handle, this.length, this.path);

  /// Opens [path] for reading and returns a new reader.
  factory MmapReader.open(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('File does not exist', path);
    }
    final handle = file.openSync();
    return MmapReader._(handle, file.lengthSync(), path);
  }

  final RandomAccessFile _handle;

  /// Total length of the file in bytes.
  final int length;

  /// Absolute path of the file.
  final String path;

  bool _closed = false;

  /// Reads [count] bytes starting at [offset]. Returns a fresh
  /// [Uint8List]; the reader does not share buffers with the caller.
  Uint8List read(int offset, int count) {
    _ensureOpen();
    if (offset < 0 || count < 0) {
      throw ArgumentError('offset and count must be non-negative');
    }
    if (offset + count > length) {
      throw RangeError('read past end of file ($offset + $count > $length)');
    }
    _handle.setPositionSync(offset);
    return _handle.readSync(count);
  }

  /// Reads bytes in [blockSize] chunks and yields them as a lazy
  /// iterable — useful for streaming processing like Merkle tree
  /// construction. The consumer MUST copy each chunk before requesting
  /// the next one if it wants to retain the data.
  Iterable<Uint8List> readBlocks({int blockSize = 65536}) sync* {
    _ensureOpen();
    if (blockSize <= 0) {
      throw ArgumentError.value(blockSize, 'blockSize', 'must be positive');
    }
    var offset = 0;
    while (offset < length) {
      final count = (length - offset) < blockSize ? (length - offset) : blockSize;
      yield read(offset, count);
      offset += count;
    }
  }

  /// Returns the first [count] bytes. Shortcut for header sniffing.
  Uint8List readHeader(int count) => read(0, count);

  /// Closes the underlying handle. Further reads throw.
  void close() {
    if (_closed) return;
    _closed = true;
    _handle.closeSync();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('MmapReader is closed');
    }
  }
}

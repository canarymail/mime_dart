/// Web implementation for platform-specific file operations.
///
/// This implementation provides a stub File class that throws
/// UnsupportedError when used, since dart:io is not available on web.
library io_web;

/// A stub File class for web platform.
///
/// File operations are not supported on web.
/// Use `PartBuilder.addBinary` instead of `PartBuilder.addFile`
/// for web-compatible file attachments.
class File {
  /// Creates a file stub that will throw when used
  File(String path) : _path = path;

  final String _path;

  /// Gets the file path
  String get path => _path;

  /// Reads the file as bytes - not supported on web
  Future<List<int>> readAsBytes() {
    throw UnsupportedError(
      'File.readAsBytes() is not supported on web. '
      'Use PartBuilder.addBinary() instead of addFile().',
    );
  }

  /// Gets the file length - not supported on web
  Future<int> length() {
    throw UnsupportedError(
      'File.length() is not supported on web. '
      'Use PartBuilder.addBinary() instead of addFile().',
    );
  }

  /// Gets the last modified time - not supported on web
  DateTime lastModifiedSync() {
    throw UnsupportedError(
      'File.lastModifiedSync() is not supported on web. '
      'Use PartBuilder.addBinary() instead of addFile().',
    );
  }
}


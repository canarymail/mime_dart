/// Stub implementation for platform-specific file operations.
///
/// This file defines the interface that must be implemented by
/// platform-specific implementations (io_native.dart, io_web.dart).
library io_stub;

/// A stub class representing a file.
///
/// On native platforms (io_native.dart), this will be dart:io's File.
/// On web platforms (io_web.dart), this will be an unsupported stub.
class File {
  /// Creates a file stub
  // ignore: avoid_unused_constructor_parameters
  File(String path) {
    throw UnsupportedError(
      'File operations are not supported on this platform. '
      'Use addBinary() instead of addFile() for web compatibility.',
    );
  }

  /// Gets the file path
  String get path => throw UnsupportedError('Not supported on web');

  /// Reads the file as bytes
  Future<List<int>> readAsBytes() =>
      throw UnsupportedError('Not supported on web');

  /// Gets the file length
  Future<int> length() => throw UnsupportedError('Not supported on web');

  /// Gets the last modified time
  DateTime lastModifiedSync() => throw UnsupportedError('Not supported on web');
}


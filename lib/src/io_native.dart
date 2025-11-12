/// Native implementation for platform-specific file operations.
///
/// This implementation uses dart:io which is available on
/// native platforms (Android, iOS, Linux, macOS, Windows).
library io_native;

// Re-export File from dart:io for native platforms
export 'dart:io' show File;


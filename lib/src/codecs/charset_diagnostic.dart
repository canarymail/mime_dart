/// The outcome of resolving or using a MIME charset label.
enum CharsetDiagnosticKind {
  /// The label resolved to a decoder.
  supported,

  /// The label is recognized but intentionally blocked for security.
  blocked,

  /// The label is recognized but has no meaningful mail interpretation.
  unsupported,

  /// The label is not present in the supported registries.
  unknown,

  /// A decoder was found but the input contained malformed or undefined bytes.
  decodeFailure,
}

/// Where the charset label was used.
enum CharsetDiagnosticSource {
  /// RFC 2047 encoded header text.
  header,

  /// A MIME part body.
  body,
}

/// Structured, content-free information about MIME charset handling.
///
/// Labels are sanitized and capped before this object is created. No message
/// body, subject, sender, recipient, or other message content is included.
class CharsetDiagnostic {
  /// Creates a charset diagnostic.
  const CharsetDiagnostic({
    required this.kind,
    required this.source,
    required this.label,
    this.canonicalName,
    this.replacementCount = 0,
  });

  /// Recreates a diagnostic sent across an isolate boundary.
  factory CharsetDiagnostic.fromMap(Map<Object?, Object?> map) =>
      CharsetDiagnostic(
        kind: CharsetDiagnosticKind.values[map['kind']! as int],
        source: CharsetDiagnosticSource.values[map['source']! as int],
        label: map['label']! as String,
        canonicalName: map['canonicalName'] as String?,
        replacementCount: map['replacementCount']! as int,
      );

  /// Resolution or decoding outcome.
  final CharsetDiagnosticKind kind;

  /// Header or body decode path.
  final CharsetDiagnosticSource source;

  /// Sanitized, normalized label.
  final String label;

  /// Canonical codec name, when one resolved.
  final String? canonicalName;

  /// Number of U+FFFD replacements in a successful malformed-input recovery.
  ///
  /// This is counted only after strict decoding fails and replacement-mode
  /// decoding succeeds. A literal U+FFFD in otherwise valid input is therefore
  /// not counted.
  final int replacementCount;

  /// Converts the diagnostic to isolate-safe scalar data.
  Map<String, Object?> toMap() => {
        'kind': kind.index,
        'source': source.index,
        'label': label,
        'canonicalName': canonicalName,
        'replacementCount': replacementCount,
      };
}

/// Receives structured MIME charset diagnostics.
typedef CharsetDiagnosticHandler = void Function(CharsetDiagnostic diagnostic);

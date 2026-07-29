import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:mime_convert/mime_convert.dart';

import '../mail_conventions.dart';
import '../private/util/ascii_runes.dart';
import 'base64_mail_codec.dart';
import 'charset_diagnostic.dart';
import 'generated_charset_registry.dart';
import 'quoted_printable_mail_codec.dart';

/// The used header encoding mechanism
enum HeaderEncoding {
  /// Q encoding similar to QuotedPrintable
  Q,

  /// Base64 encoding
  B,

  /// No encoding
  none
}

class _CharsetResolution {
  const _CharsetResolution({
    required this.label,
    this.canonicalName,
    this.codec,
    this.lenientCodec,
    this.failureKind,
  });

  final String label;
  final String? canonicalName;

  /// Strict codec used to distinguish valid text from malformed input.
  final convert.Encoding? codec;

  /// Replacement-mode codec used to preserve readable output after failure.
  final convert.Encoding? lenientCodec;
  final CharsetDiagnosticKind? failureKind;
}

/// Encodes and decodes base-64 and quoted printable encoded texts
///
/// Compare https://tools.ietf.org/html/rfc2045#page-19
/// and https://tools.ietf.org/html/rfc2045#page-23 for details
abstract class MailCodec {
  /// Creates a new mail codec
  const MailCodec();

  /// Receives content-free charset resolution and decoding diagnostics.
  ///
  /// The handler is isolate-local. Applications parsing in background
  /// isolates should install a handler in each isolate and forward the
  /// diagnostic's scalar [CharsetDiagnostic.toMap] representation.
  static CharsetDiagnosticHandler? charsetDiagnosticHandler;

  /// No transfer encoding
  static const String contentTransferEncodingNone = 'none';

  /// Typical maximum length of a single text line
  static const String _encodingEndSequence = '?=';
  static final _headerEncodingExpression = RegExp(
    r'\=\?.+?\?.+?\?.+?\?\=',
  ); // the question marks after plus make this regular expression non-greedy
  static final _emptyHeaderEncodingExpression = RegExp(r'\=\?.+?\?.+?\?\?\=');

  /// UTF8 encoding
  static const encodingUtf8 = convert.Utf8Codec(allowMalformed: true);

  /// ISO-8859-1 encoding
  static const encodingLatin1 = convert.Latin1Codec(allowInvalid: true);

  /// ASCII encoding
  static const encodingAscii = convert.AsciiCodec(allowInvalid: true);

  static final Map<String, String> _separatorFoldedCharsetLabels =
      _buildSeparatorFoldedCharsetLabels();
  static final Set<String> _separatorFoldedBlockedLabels =
      knownBlockedCharsetLabels.map(_foldCharsetSeparators).toSet();
  static final Set<String> _separatorFoldedUnsupportedLabels =
      knownUnsupportedCharsetLabels.map(_foldCharsetSeparators).toSet();

  static Map<String, String> _buildSeparatorFoldedCharsetLabels() {
    final result = <String, String>{};
    final collisions = <String>{};
    for (final entries in [
      whatwgCharsetLabels.entries,
      pythonMimeCharsetAliases.entries,
    ]) {
      for (final entry in entries) {
        final folded = _foldCharsetSeparators(entry.key);
        final previous = result[folded];
        if (previous == null || previous == entry.value) {
          result[folded] = entry.value;
        } else {
          collisions.add(folded);
        }
      }
    }
    collisions.forEach(result.remove);
    return result;
  }

  static String _foldCharsetSeparators(String value) =>
      value.replaceAll(RegExp(r'[ _-]'), '');

  static String _normalizeCharsetLabel(String name) {
    var normalized = name.trim().toLowerCase();
    if (normalized.length > 1 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    final star = normalized.indexOf('*');
    if (star > 0) {
      normalized = normalized.substring(0, star);
    }
    return normalized;
  }

  static String _sanitizeCharsetLabel(String label) {
    final buffer = StringBuffer();
    for (final rune in label.runes) {
      if (buffer.length >= 80) {
        break;
      }
      buffer
          .write(rune < 0x20 || rune == 0x7F ? '?' : String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  static CharsetDiagnosticKind? _failureKindForLabel(String label) {
    final exactCandidates = <String>[
      label,
      if (label.startsWith('x-')) label.substring(2),
    ];
    final folded = _foldCharsetSeparators(label);
    final foldedCandidates = <String>[
      folded,
      if (folded.startsWith('x')) folded.substring(1),
    ];
    for (final candidate in exactCandidates) {
      if (knownBlockedCharsetLabels.contains(candidate)) {
        return CharsetDiagnosticKind.blocked;
      }
      if (knownUnsupportedCharsetLabels.contains(candidate)) {
        return CharsetDiagnosticKind.unsupported;
      }
    }
    if (foldedCandidates.any(_separatorFoldedBlockedLabels.contains)) {
      return CharsetDiagnosticKind.blocked;
    }
    if (foldedCandidates.any(_separatorFoldedUnsupportedLabels.contains)) {
      return CharsetDiagnosticKind.unsupported;
    }
    return null;
  }

  static convert.Encoding? _codecForCanonicalName(
    String canonicalName, {
    required bool allowInvalid,
  }) {
    switch (canonicalName) {
      case 'utf-8':
        return convert.Utf8Codec(allowMalformed: allowInvalid);
      case 'utf-8-sig':
        return Utf8SigCodec(allowInvalid: allowInvalid);
      case 'utf-16':
        return Utf16Codec(allowInvalid: allowInvalid);
      case 'utf-16le':
        return Utf16LeCodec(
          allowInvalid: allowInvalid,
          bomAware: true,
        );
      case 'utf-16be':
        return Utf16BeCodec(
          allowInvalid: allowInvalid,
          bomAware: true,
        );
      case 'iso-8859-2':
        return Latin2Codec(allowInvalid: allowInvalid);
      case 'iso-8859-3':
        return Latin3Codec(allowInvalid: allowInvalid);
      case 'iso-8859-4':
        return Latin4Codec(allowInvalid: allowInvalid);
      case 'iso-8859-5':
        return Latin5Codec(allowInvalid: allowInvalid);
      case 'iso-8859-6':
        return Latin6Codec(allowInvalid: allowInvalid);
      case 'iso-8859-7':
        return Latin7Codec(allowInvalid: allowInvalid);
      case 'iso-8859-8':
      case 'iso-8859-8-i':
        return Latin8Codec(allowInvalid: allowInvalid);
      case 'iso-8859-10':
        return Latin10Codec(allowInvalid: allowInvalid);
      case 'iso-8859-13':
        return Latin13Codec(allowInvalid: allowInvalid);
      case 'iso-8859-14':
        return Latin14Codec(allowInvalid: allowInvalid);
      case 'iso-8859-15':
        return Latin15Codec(allowInvalid: allowInvalid);
      case 'iso-8859-16':
        return Latin16Codec(allowInvalid: allowInvalid);
      case 'windows-1250':
        return Windows1250Codec(allowInvalid: allowInvalid);
      case 'windows-1251':
        return Windows1251Codec(allowInvalid: allowInvalid);
      case 'windows-1252':
        return Windows1252Codec(allowInvalid: allowInvalid);
      case 'windows-1253':
        return Windows1253Codec(allowInvalid: allowInvalid);
      case 'windows-1254':
        return Windows1254Codec(allowInvalid: allowInvalid);
      case 'windows-1256':
        return Windows1256Codec(allowInvalid: allowInvalid);
      case 'cp850':
        return CodePage850Codec(allowInvalid: allowInvalid);
      case 'koi8-r':
        return Koi8rCodec(allowInvalid: allowInvalid);
      case 'koi8-u':
        return Koi8uCodec(allowInvalid: allowInvalid);
      case 'gbk':
        return GbkCodec(allowInvalid: allowInvalid);
      case 'gb18030':
        return Gb18030Codec(allowInvalid: allowInvalid);
      case 'big5':
        return Big5Codec(allowInvalid: allowInvalid);
      case 'shift_jis':
        return ShiftJisCodec(allowInvalid: allowInvalid);
      case 'euc-jp':
        return EucJpCodec(allowInvalid: allowInvalid);
      case 'euc-kr':
        return EucKrCodec(allowInvalid: allowInvalid);
      case 'iso-2022-jp':
        return Iso2022JpCodec(allowInvalid: allowInvalid);
    }
    final pythonName = generatedSingleByteCodecNames[canonicalName];
    return pythonName == null
        ? null
        : generatedSingleByteCodec(pythonName, allowInvalid: allowInvalid);
  }

  static _CharsetResolution _resolveCharset(
    String name,
    CharsetDiagnosticSource source,
  ) {
    final normalized = _normalizeCharsetLabel(name);
    final safeLabel = _sanitizeCharsetLabel(normalized);

    final failureKind = _failureKindForLabel(normalized);
    if (failureKind != null) {
      _emitCharsetDiagnostic(
        kind: failureKind,
        source: source,
        label: safeLabel,
      );
      return _CharsetResolution(label: safeLabel, failureKind: failureKind);
    }

    var lookupLabel = normalized;
    var canonicalName = whatwgCharsetLabels[lookupLabel] ??
        pythonMimeCharsetAliases[lookupLabel];
    if (canonicalName == null && lookupLabel.startsWith('x-')) {
      lookupLabel = lookupLabel.substring(2);
      canonicalName = whatwgCharsetLabels[lookupLabel] ??
          pythonMimeCharsetAliases[lookupLabel];
    }
    canonicalName ??=
        _separatorFoldedCharsetLabels[_foldCharsetSeparators(lookupLabel)];
    final codec = canonicalName == null
        ? null
        : _codecForCanonicalName(canonicalName, allowInvalid: false);
    final lenientCodec = canonicalName == null
        ? null
        : _codecForCanonicalName(canonicalName, allowInvalid: true);
    if (codec == null) {
      _emitCharsetDiagnostic(
        kind: CharsetDiagnosticKind.unknown,
        source: source,
        label: safeLabel,
        canonicalName: canonicalName,
      );
      return _CharsetResolution(
        label: safeLabel,
        canonicalName: canonicalName,
        failureKind: CharsetDiagnosticKind.unknown,
      );
    }
    return _CharsetResolution(
      label: safeLabel,
      canonicalName: canonicalName,
      codec: codec,
      lenientCodec: lenientCodec,
    );
  }

  static void _emitCharsetDiagnostic({
    required CharsetDiagnosticKind kind,
    required CharsetDiagnosticSource source,
    required String label,
    String? canonicalName,
    int replacementCount = 0,
  }) {
    charsetDiagnosticHandler?.call(
      CharsetDiagnostic(
        kind: kind,
        source: source,
        label: label,
        canonicalName: canonicalName,
        replacementCount: replacementCount,
      ),
    );
  }

  static String _decodeWithCharsetDiagnostic(
    _CharsetResolution resolution,
    CharsetDiagnosticSource source,
    String Function(convert.Encoding codec) decode,
    String fallback,
  ) {
    final codec = resolution.codec;
    final lenientCodec = resolution.lenientCodec;
    if (codec == null || lenientCodec == null) {
      return fallback;
    }
    if (charsetDiagnosticHandler == null) {
      return decode(lenientCodec);
    }
    try {
      final decoded = decode(codec);
      _emitCharsetDiagnostic(
        kind: CharsetDiagnosticKind.supported,
        source: source,
        label: resolution.label,
        canonicalName: resolution.canonicalName,
      );
      return decoded;
    } on FormatException {
      String decoded;
      try {
        decoded = decode(lenientCodec);
      } on FormatException {
        decoded = fallback;
      }
      _emitCharsetDiagnostic(
        kind: CharsetDiagnosticKind.decodeFailure,
        source: source,
        label: resolution.label,
        canonicalName: resolution.canonicalName,
      );
      return decoded;
    }
  }

  static final _textDecodersByName = <String,
      String Function(
    String text,
    convert.Encoding encoding, {
    required bool isHeader,
  })>{
    'q': quotedPrintable.decodeText,
    'quoted-printable': quotedPrintable.decodeText,
    'b': base64.decodeText,
    'base64': base64.decodeText,
    'base-64': base64.decodeText,
    '7bit': decodeOnlyCodec,
    '8bit': decodeOnlyCodec,
    contentTransferEncodingNone: decodeOnlyCodec,
  };

  static final _binaryDecodersByName = <String, Uint8List Function(String)>{
    'b': base64.decodeData,
    'base64': base64.decodeData,
    'base-64': base64.decodeData,
    'binary': decodeBinaryTextData,
    '8bit': decode8BitTextData,
    contentTransferEncodingNone: decode8BitTextData,
  };

  /// bas64 mail codec
  static const base64 = Base64MailCodec();

  /// quoted printable mail codec
  static const quotedPrintable = QuotedPrintableMailCodec();

  /// Encodes the specified text in the chosen codec's format.
  ///
  /// [text] specifies the text to be encoded.
  /// [codec] the optional codec, which defaults to utf8.
  /// Set [wrap] to false in case you do not want to wrap lines.
  String encodeText(
    String text, {
    convert.Codec codec = encodingUtf8,
    bool wrap = true,
  });

  /// Encodes the header text in the chosen codec's only if required.
  ///
  /// [text] specifies the text to be encoded.
  /// Set the optional [fromStart] to true in case the encoding should
  /// start at the beginning of the text and not in the middle.
  String encodeHeader(
    String text, {
    bool fromStart = false,
  });

  /// Encodes the given [part] text.
  Uint8List decodeData(String part);

  /// Decodes the given [part] text with the given [codec].
  ///
  /// [isHeader] is set to the `true` when this text originates from a header
  String decodeText(
    String part,
    convert.Encoding codec, {
    bool isHeader = false,
  });

  /// Decodes the given header [input] value.
  static String? decodeHeader(final String? input) {
    if (input == null || input.isEmpty) {
      return input;
    }
    // unwrap any lines:
    var cleaned = input.replaceAll('\r\n ', '');
    // remove any spaces between 2 encoded words:
    final containsEncodedWordsWithSpace = cleaned.contains('?= =?');
    final containsEncodedWordsWithTab = cleaned.contains('?=\t=?');
    final containsEncodedWordsWithoutSpace =
        !containsEncodedWordsWithSpace && cleaned.contains('?==?');
    if (containsEncodedWordsWithSpace ||
        containsEncodedWordsWithTab ||
        containsEncodedWordsWithoutSpace) {
      final match = _headerEncodingExpression.firstMatch(cleaned);
      if (match != null) {
        final sequence = match.group(0) ?? '';
        final separatorIndex = sequence.indexOf('?', 3);
        final endIndex = separatorIndex + 3;
        final startSequence = sequence.substring(0, endIndex);
        final searchText = containsEncodedWordsWithSpace
            ? '?= $startSequence'
            : containsEncodedWordsWithTab
                ? '?=\t$startSequence'
                : '?=$startSequence';
        if (startSequence.endsWith('?B?') || startSequence.endsWith('?b?')) {
          // in base64 encoding there are 2 cases:
          // 1. individual parts can end  with the padding character "=":
          //    - in that case we just remove the
          //      space between the encoded words
          // 2. individual words do not end with a padding character:
          //    - in that case we combine the words
          if (cleaned.contains('=$searchText')) {
            if (containsEncodedWordsWithSpace) {
              cleaned = cleaned.replaceAll('?= =?', '?==?');
            } else if (containsEncodedWordsWithTab) {
              cleaned = cleaned.replaceAll('?=\t=?', '?==?');
            }
          } else {
            cleaned = cleaned.replaceAll(searchText, '');
          }
        } else {
          // "standard case" - just fuse the sequences together
          cleaned = cleaned.replaceAll(searchText, '');
        }
      }
    }
    final buffer = StringBuffer();
    _decodeHeaderImpl(cleaned, buffer);

    return buffer.toString();
  }

  static void _decodeHeaderImpl(final String input, StringBuffer buffer) {
    RegExpMatch? match;
    var reminder = input;
    while ((match = _headerEncodingExpression.firstMatch(reminder)) != null) {
      final sequence = match?.group(0) ?? '';
      final separatorIndex = sequence.indexOf('?', 3);
      final characterEncodingName =
          sequence.substring('=?'.length, separatorIndex).toLowerCase();
      final decoderName = sequence
          .substring(separatorIndex + 1, separatorIndex + 2)
          .toLowerCase();

      final resolution = _resolveCharset(
        characterEncodingName,
        CharsetDiagnosticSource.header,
      );
      if (match != null && match.start > 0) {
        buffer.write(reminder.substring(0, match.start));
      }
      if (resolution.codec == null) {
        // Preserve only this encoded word, then continue so a later valid word
        // in the same header can still be decoded.
        buffer.write(sequence);
        reminder = reminder.substring(match?.end ?? 0);
        continue;
      }
      final decoder = _textDecodersByName[decoderName];
      if (decoder == null) {
        buffer.write(sequence);
        reminder = reminder.substring(match?.end ?? 0);
        continue;
      }
      final contentStartIndex = separatorIndex + 3;
      final part = sequence.substring(
        contentStartIndex,
        sequence.length - _encodingEndSequence.length,
      );
      final decoded = _decodeWithCharsetDiagnostic(
        resolution,
        CharsetDiagnosticSource.header,
        (codec) => decoder(part, codec, isHeader: true),
        sequence,
      );
      buffer.write(decoded);
      reminder = reminder.substring(match?.end ?? 0);
    }
    if (buffer.isEmpty &&
        reminder.startsWith('=?') &&
        _emptyHeaderEncodingExpression.hasMatch(reminder)) {
      return;
    }
    buffer.write(reminder);
  }

  /// Detects the encoding used in the given header [value].
  static HeaderEncoding detectHeaderEncoding(String value) {
    final match = _headerEncodingExpression.firstMatch(value);
    if (match == null) {
      return HeaderEncoding.none;
    }
    final group = match.group(0);

    return group?.contains('?B?') ?? group?.contains('?b?') ?? false
        ? HeaderEncoding.B
        : HeaderEncoding.Q;
  }

  /// Decodes the given binary [text]
  static Uint8List decodeBinary(
    final String text,
    final String? transferEncoding,
  ) {
    final tEncoding = transferEncoding ?? contentTransferEncodingNone;
    final decoder = _binaryDecodersByName[tEncoding.toLowerCase()];
    if (decoder == null) {
      print('Error: no binary decoder found for [$tEncoding].');

      return Uint8List.fromList(text.codeUnits);
    }

    return decoder(text);
  }

  /// Decodes the given [data]
  static String decodeAsText(
    final Uint8List data,
    final String? transferEncoding,
    final String? charset,
  ) {
    if (transferEncoding == null && charset == null) {
      // this could be a) UTF-8 or b) UTF-16 most likely:
      final utf8Decoded = encodingUtf8.decode(data, allowMalformed: true);
      if (utf8Decoded.contains('�')) {
        final comparison = String.fromCharCodes(data);
        if (!comparison.contains('�')) {
          return comparison;
        }
      }

      return utf8Decoded;
    }
    // there is actually just one interesting case:
    // when the transfer encoding is 8bit, the text needs to be decoded with
    // the specified charset.
    // Note that some mail senders also declare 7bit message encoding even when
    // UTF8 or other 8bit encodings are used.
    // In other cases the text is ASCII and the 'normal' decodeAnyText method
    // can be used.
    final transferEncodingLC = transferEncoding?.toLowerCase() ?? '8bit';
    if (transferEncodingLC == '8bit' ||
        transferEncodingLC == '7bit' ||
        transferEncodingLC == 'binary') {
      final cs = charset ?? 'utf8';
      final resolution = _resolveCharset(cs, CharsetDiagnosticSource.body);
      if (resolution.codec == null) {
        return encodingUtf8.decode(data, allowMalformed: true);
      }
      return _decodeWithCharsetDiagnostic(
        resolution,
        CharsetDiagnosticSource.body,
        (codec) => codec.decode(data),
        encodingUtf8.decode(data, allowMalformed: true),
      );
    }
    final text = String.fromCharCodes(data);

    return decodeAnyText(text, transferEncoding, charset);
  }

  /// Decodes the given [text]
  static String decodeAnyText(
    final String text,
    final String? transferEncoding,
    final String? charset,
  ) {
    final transferEnc = transferEncoding ?? contentTransferEncodingNone;
    final decoder = _textDecodersByName[transferEnc.toLowerCase()];
    if (decoder == null) {
      print('Error: no decoder found for '
          'content-transfer-encoding [$transferEnc].');

      return text;
    }
    final cs = charset ?? 'utf8';
    final resolution = _resolveCharset(cs, CharsetDiagnosticSource.body);
    if (resolution.codec == null) {
      return text;
    }

    return _decodeWithCharsetDiagnostic(
      resolution,
      CharsetDiagnosticSource.body,
      (codec) => decoder(text, codec, isHeader: false),
      text,
    );
  }

  /// Decodes binary from the given text [part].
  static Uint8List decodeBinaryTextData(String part) =>
      Uint8List.fromList(part.codeUnits);

  /// Decodes the data from the given 8bit text [part]
  static Uint8List decode8BitTextData(final String part) =>
      Uint8List.fromList(part.replaceAll('\r\n', '').codeUnits);

  /// Is a noop
  static String decodeOnlyCodec(
    String part,
    convert.Encoding codec, {
    bool isHeader = false,
  }) =>
      part;

  /// Wraps the text so that it stays within email's 76 characters
  /// per line convention.
  ///
  /// [text] the text that should be wrapped.
  /// Set [wrapAtWordBoundary] to true in case the text should be wrapped
  /// at word boundaries / spaces.
  static String wrapText(String text, {bool wrapAtWordBoundary = false}) {
    if (text.length <= MailConventions.textLineMaxLength) {
      return text;
    }
    final buffer = StringBuffer();
    final runes = text.runes;
    int? lastRune;
    int? lastSpaceIndex;
    var currentLineLength = 0;
    var currentLineStartIndex = 0;
    for (var runeIndex = 0; runeIndex < runes.length; runeIndex++) {
      final rune = runes.elementAt(runeIndex);
      if (rune == AsciiRunes.runeLineFeed &&
          lastRune == AsciiRunes.runeCarriageReturn) {
        buffer.write(text.substring(currentLineStartIndex, runeIndex + 1));
        currentLineLength = 0;
        currentLineStartIndex = runeIndex + 1;
        lastSpaceIndex = null;
      } else {
        if (wrapAtWordBoundary &&
            (rune == AsciiRunes.runeSpace || rune == AsciiRunes.runeTab)) {
          lastSpaceIndex = runeIndex;
        }
        currentLineLength++;
        if (currentLineLength >= MailConventions.textLineMaxLength) {
          // edge case: this could be in the middle of a \r\n sequence:
          if (rune == AsciiRunes.runeCarriageReturn &&
              runeIndex < runes.length - 1 &&
              runes.elementAt(runeIndex + 1) == AsciiRunes.runeLineFeed) {
            lastRune = rune;
            continue; // the break will be handled in the next loop iteration
          }
          var endIndex = (wrapAtWordBoundary && lastSpaceIndex != null)
              ? lastSpaceIndex
              : runeIndex;
          if (endIndex < runes.length - 1) {
            endIndex++;
          }
          buffer
            ..write(text.substring(currentLineStartIndex, endIndex))
            ..write('\r\n');
          currentLineLength = 0;
          currentLineStartIndex = endIndex;
          lastSpaceIndex = null;
        }
      }
      lastRune = rune;
    }

    if (currentLineStartIndex < text.length) {
      buffer.write(text.substring(currentLineStartIndex));
    }

    return buffer.toString();
  }
}

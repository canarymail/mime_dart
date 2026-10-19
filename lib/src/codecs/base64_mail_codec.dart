import 'dart:convert';
import 'dart:typed_data';

import '../mail_conventions.dart';
import '../private/util/ascii_runes.dart';
import '../private/util/encoded_words.dart';
import 'mail_codec.dart';

/// Provides base64 encoder and decoder.
///
/// Compare https://tools.ietf.org/html/rfc2045#page-23 for details.
class Base64MailCodec extends MailCodec {
  /// Creates a new base64 mail codec
  const Base64MailCodec();

  static const String _base64Alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  /// Marks a code unit that is not part of either base64 alphabet.
  static const int _notBase64 = 0xFF;

  /// Maps an ASCII code unit to its 6-bit value, accepting the URL-safe
  /// alphabet alongside the standard one just as Dart's own decoder does.
  static final Uint8List _inverseAlphabet = _buildInverseAlphabet();

  static Uint8List _buildInverseAlphabet() {
    final table = Uint8List(128)..fillRange(0, 128, _notBase64);
    for (var i = 0; i < _base64Alphabet.length; i++) {
      table[_base64Alphabet.codeUnitAt(i)] = i;
    }
    table[AsciiRunes.runeMinus] = 62;
    table[AsciiRunes.runeUnderline] = 63;

    return table;
  }

  /// Encodes the specified text in base64 format.
  ///
  /// [text] specifies the text to be encoded.
  /// [codec] the optional codec, defaults to utf8 [MailCodec.encodingUtf8].
  /// Set [wrap] to `false` in case you do not want to wrap lines.
  @override
  String encodeText(
    String text, {
    Codec codec = MailCodec.encodingUtf8,
    bool wrap = true,
  }) {
    final charCodes = codec.encode(text);

    return encodeData(charCodes, wrap: wrap);
  }

  /// Encodes the header text in base64 only if required.
  ///
  /// [text] specifies the text to be encoded.
  /// Set the optional [fromStart] to true in case the encoding should
  /// start at the beginning of the text and not at the first word that
  /// needs it.
  /// Set the [nameLength] for ensuring there is enough place for the
  /// name of the encoding.
  @override
  String encodeHeader(
    String text, {
    int nameLength = 0,
    bool fromStart = false,
  }) =>
      EncodedWords.encodeHeaderText(
        text,
        useBase64: true,
        nameLength: nameLength,
        fromStart: fromStart,
      );

  @override
  Uint8List decodeData(final String part) {
    // Remove all whitespace characters per RFC 2045:
    // "Any characters outside of the base64 alphabet are to be ignored in
    // base64-encoded data."
    // This includes spaces (ASCII 32), tabs (ASCII 9), newlines (ASCII 10),
    // and carriage returns (ASCII 13).
    var cleaned = part.replaceAll(RegExp(r'\s'), '');
    var numberOfRequiredPadding =
        cleaned.length % 4 == 0 ? 0 : 4 - cleaned.length % 4;
    if (numberOfRequiredPadding > 0 && cleaned.endsWith('=')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
      numberOfRequiredPadding =
          cleaned.length % 4 == 0 ? 0 : 4 - cleaned.length % 4;
    }
    if (numberOfRequiredPadding > 0) {
      final buffer = StringBuffer(cleaned);
      var paddingRequired = true;
      while (paddingRequired) {
        buffer.write('=');
        numberOfRequiredPadding--;
        paddingRequired = numberOfRequiredPadding > 0;
      }
      cleaned = buffer.toString();
    }

    try {
      return base64.decode(cleaned);
    } on FormatException {
      // Dart's decoder is stricter than RFC 2045 requires. It rejects
      // characters outside the alphabet, and a final quantum whose unused
      // low bits are non-zero -- some senders emit 'Pn==' for '>' rather
      // than the canonical 'Pg==' -- which the RFC says to discard. Repair
      // those rather than losing the whole part.
      return base64.decode(_canonicalize(cleaned));
    }
  }

  /// Rewrites [data] into canonical base64: characters outside the alphabet
  /// are dropped, and the final quantum's discarded bits are zeroed.
  String _canonicalize(String data) {
    final buffer = StringBuffer();
    for (var i = 0; i < data.length; i++) {
      final value = _sixBitValue(data.codeUnitAt(i));
      if (value != _notBase64) {
        buffer.writeCharCode(_base64Alphabet.codeUnitAt(value));
      }
    }
    final normalized = buffer.toString();
    switch (normalized.length % 4) {
      case 1:
        // A lone trailing character cannot encode a byte.
        return normalized.substring(0, normalized.length - 1);
      case 2:
        // 2 characters encode 1 byte, so the last 4 bits are discarded.
        return '${_maskLast(normalized, 0x30)}==';
      case 3:
        // 3 characters encode 2 bytes, so the last 2 bits are discarded.
        return '${_maskLast(normalized, 0x3C)}=';
      default:
        return normalized;
    }
  }

  String _maskLast(String data, int mask) {
    final masked = _sixBitValue(data.codeUnitAt(data.length - 1)) & mask;

    return '${data.substring(0, data.length - 1)}'
        '${_base64Alphabet[masked]}';
  }

  int _sixBitValue(int codeUnit) => codeUnit < _inverseAlphabet.length
      ? _inverseAlphabet[codeUnit]
      : _notBase64;

  @override
  String decodeText(String part, Encoding codec, {bool isHeader = false}) {
    final outputList = decodeData(part);

    return codec.decode(outputList);
  }

  /// Encodes the specified [data] in base64 format.
  /// Set [wrap] to false in case you do not want to wrap lines.
  String encodeData(List<int> data, {bool wrap = true}) {
    var base64Text = base64.encode(data);
    if (wrap) {
      base64Text = _wrapText(base64Text);
    }

    return base64Text;
  }

  String _wrapText(String text) {
    const chunkLength = MailConventions.textLineMaxLength;
    var length = text.length;
    if (length <= chunkLength) {
      return text;
    }
    var chunkIndex = 0;
    final buffer = StringBuffer();
    // ignore: invariant_booleans
    while (length > chunkLength) {
      final startPos = chunkIndex * chunkLength;
      final endPos = startPos + chunkLength;
      buffer
        ..write(text.substring(startPos, endPos))
        ..write('\r\n');
      chunkIndex++;
      length -= chunkLength;
    }
    if (length > 0) {
      final startPos = chunkIndex * chunkLength;
      buffer.write(text.substring(startPos));
    }

    return buffer.toString();
  }
}

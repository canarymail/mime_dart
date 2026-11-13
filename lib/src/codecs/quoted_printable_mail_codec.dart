import 'dart:convert';
import 'dart:typed_data';

import '../mail_conventions.dart';
import '../private/util/ascii_runes.dart';
import '../private/util/encoded_words.dart';
import 'mail_codec.dart';

/// Provides quoted printable encoder and decoder.
///
/// Compare https://tools.ietf.org/html/rfc2045#page-19 for details.
class QuotedPrintableMailCodec extends MailCodec {
  /// Creates a new quoted printable codec
  const QuotedPrintableMailCodec();

  /// Encodes the specified text in quoted printable format.
  ///
  /// [text] specifies the text to be encoded.
  /// [codec] the optional codec, which defaults to utf8.
  /// Set [wrap] to false in case you do not want to wrap lines.
  @override
  String encodeText(
    final String text, {
    Codec codec = MailCodec.encodingUtf8,
    bool wrap = true,
  }) {
    final buffer = StringBuffer();
    final runes = List.from(text.runes);
    final runeCount = runes.length;

    var lineCharacterCount = 0;

    for (var i = 0; i < runeCount; i++) {
      final rune = runes[i];
      if ((rune >= 32 && rune <= 60) ||
          (rune >= 62 && rune <= 126) ||
          rune == 9) {
        buffer.writeCharCode(rune);
        lineCharacterCount++;
      } else {
        if (i < runeCount - 1 &&
            rune == AsciiRunes.runeCarriageReturn &&
            runes[i + 1] == AsciiRunes.runeLineFeed) {
          buffer.write('\r\n');
          i++;
          lineCharacterCount = 0;
        } else if (rune == AsciiRunes.runeLineFeed) {
          buffer.write('\r\n');
          lineCharacterCount = 0;
        } else {
          //TODO some characters consist of more than a single rune
          lineCharacterCount += _writeQuotedPrintable(rune, buffer, codec);
        }
      }
      if (wrap && lineCharacterCount >= MailConventions.textLineMaxLength - 1) {
        buffer.write('=\r\n'); // soft line break
        lineCharacterCount = 0;
      }
    }

    return buffer.toString();
  }

  /// Encodes the header text in Q encoding only if required.
  ///
  /// Compare https://tools.ietf.org/html/rfc2047#section-4.2 for details.
  /// [text] specifies the text to be encoded.
  /// [nameLength] the length of the header name, for calculating the wrapping
  ///  point.
  /// [codec] is ignored: encoded-words are always written in UTF-8.
  /// Set the optional [fromStart] to true in case the encoding should  start
  /// at the beginning of the text and not at the first word that needs it.
  @override
  String encodeHeader(
    final String text, {
    int nameLength = 0,
    Codec codec = utf8,
    bool fromStart = false,
  }) =>
      EncodedWords.encodeHeaderText(
        text,
        useBase64: false,
        nameLength: nameLength,
        fromStart: fromStart,
      );

  /// Decodes the specified text
  ///
  /// [part] the text part that should be decoded
  /// [codec] the character encoding (charset)
  /// Set [isHeader] to true to decode header text using the Q-Encoding scheme,
  /// compare https://tools.ietf.org/html/rfc2047#section-4.2
  @override
  String decodeText(
    final String part,
    final Encoding codec, {
    bool isHeader = false,
  }) =>
      _decodeText(
        part,
        codec,
        isHeader: isHeader,
        propagateCodecErrors: false,
      );

  /// Decodes text while allowing strict charset failures to reach the caller.
  ///
  /// [MailCodec] uses this variant so it can retry with the corresponding
  /// replacement-mode charset and emit an accurate diagnostic. Direct users
  /// of [decodeText] retain its historical best-effort behavior.
  String decodeTextStrict(
    final String part,
    final Encoding codec, {
    bool isHeader = false,
  }) =>
      _decodeText(
        part,
        codec,
        isHeader: isHeader,
        propagateCodecErrors: true,
      );

  String _decodeText(
    String part,
    Encoding codec, {
    required bool isHeader,
    required bool propagateCodecErrors,
  }) {
    // remove all soft-breaks:
    final cleaned = part.replaceAll('=\r\n', '');
    // Valid quoted-printable escapes every byte >= 0x80, so undo the escapes
    // for the whole part and decode the bytes with the charset once
    // (RFC 2045 6.7). Decoding each `=XX` run on its own, as
    // [_decodeEscapedRuns] does, breaks any charset whose characters mix
    // escaped and literal bytes: ISO-2022-JP escapes only ESC (`=1B`), and a
    // Shift_JIS, GBK or Big5 trail byte can be a literal ASCII character.
    final bytes = _unescape(cleaned, isHeader: isHeader);
    if (bytes != null) {
      try {
        return codec.decode(bytes);
      } on FormatException {
        if (propagateCodecErrors) {
          // Not valid in the charset. MailCodec retries with its lenient
          // codec, which decodes the whole part with U+FFFD for the bad
          // bytes. The per-run decoding below would instead "succeed" with
          // the escapes left in (an ISO-2022-JP part with one unmapped
          // character came back as `ESC $B...`), reported as supported.
          rethrow;
        }
        // A direct best-effort call with a strict codec: decode as before.
      }
    }
    // Not valid quoted-printable (raw 8-bit bytes or text that is already
    // Unicode): decode exactly as before. Deliberately no attempt to do
    // better here: whether raw bytes are UTF-8 or Latin-1 can only be
    // guessed, and every guess decoded some text worse than before.
    return _decodeEscapedRuns(
      cleaned,
      codec,
      isHeader: isHeader,
      propagateCodecErrors: propagateCodecErrors,
    );
  }

  /// The value of the hex digit [codeUnit], or -1 when it is none.
  ///
  /// Checked by hand: `int.tryParse` accepts a sign and surrounding
  /// whitespace, which would turn a sloppy `= 1` into the control byte 0x01.
  static int _hexValue(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) {
      return codeUnit - 0x30;
    }
    final lower = codeUnit | 0x20;
    if (lower >= 0x61 && lower <= 0x66) {
      return lower - 0x61 + 10;
    }
    return -1;
  }

  /// Returns the bytes [text] encodes, or null when [text] is not valid
  /// quoted-printable because it holds a character >= 0x80 (a raw 8-bit byte
  /// or a character already decoded to Unicode).
  static Uint8List? _unescape(String text, {required bool isHeader}) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) >= 0x80) {
        return null;
      }
    }
    // Unescaping only shrinks the text, so its length bounds the bytes.
    final bytes = Uint8List(text.length);
    var length = 0;
    for (var i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      if (codeUnit == AsciiRunes.runeEquals) {
        final high =
            i + 1 < text.length ? _hexValue(text.codeUnitAt(i + 1)) : -1;
        final low =
            i + 2 < text.length ? _hexValue(text.codeUnitAt(i + 2)) : -1;
        if (high >= 0 && low >= 0) {
          bytes[length++] = high << 4 | low;
        } else {
          // Not an escape. As [_decodeEscapedRuns] does, drop the `=` and
          // copy the next two characters (or fewer at the end) unchanged:
          // in `a == b` the second `=` stays, and in a header a `_` after
          // the `=` stays an underscore.
          for (var j = i + 1; j < i + 3 && j < text.length; j++) {
            bytes[length++] = text.codeUnitAt(j);
          }
        }
        i += 2;
      } else if (isHeader && codeUnit == AsciiRunes.runeUnderline) {
        bytes[length++] = AsciiRunes.runeSpace;
      } else {
        bytes[length++] = codeUnit;
      }
    }
    return Uint8List.sublistView(bytes, 0, length);
  }

  /// The decoding before whole-part decoding, unchanged: each run of `=XX`
  /// escapes is decoded with [codec] on its own and every other character is
  /// kept as is.
  static String _decodeEscapedRuns(
    String cleaned,
    Encoding codec, {
    required bool isHeader,
    required bool propagateCodecErrors,
  }) {
    final buffer = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      final char = cleaned[i];
      if (char == '=') {
        final hexText = cleaned.substring(i + 1, i + 3);
        var charCode = int.tryParse(hexText, radix: 16);
        if (charCode == null) {
          buffer.write(hexText);
        } else {
          final charCodes = [charCode];
          while (cleaned.length > (i + 4) && cleaned[i + 3] == '=') {
            i += 3;
            final hexText = cleaned.substring(i + 1, i + 3);
            charCode = int.parse(hexText, radix: 16);
            charCodes.add(charCode);
          }

          try {
            buffer.write(codec.decode(charCodes));
          } on FormatException {
            if (propagateCodecErrors) {
              rethrow;
            }
            buffer.write(String.fromCharCodes(charCodes));
          }
        }
        i += 2;
      } else if (isHeader && char == '_') {
        buffer.write(' ');
      } else {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }

  int _writeQuotedPrintable(int rune, StringBuffer buffer, Codec codec) {
    List<int> encoded;
    if (rune < 128) {
      // this is 7 bit ASCII
      encoded = [rune];
    } else {
      final runeText = String.fromCharCode(rune);
      encoded = codec.encode(runeText);
    }
    final lengthBefore = buffer.length;
    for (final charCode in encoded) {
      final paddedHexValue = charCode.toRadixString(16).toUpperCase();
      buffer.write('=');
      if (paddedHexValue.length == 1) {
        buffer.write('0');
      }
      buffer.write(paddedHexValue);
    }

    return buffer.length - lengthBefore;
  }

  @override
  Uint8List decodeData(String part) => Uint8List.fromList(part.codeUnits);
}

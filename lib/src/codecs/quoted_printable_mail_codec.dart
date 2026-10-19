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
    final buffer = StringBuffer();
    // remove all soft-breaks:
    final cleaned = part.replaceAll('=\r\n', '');
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

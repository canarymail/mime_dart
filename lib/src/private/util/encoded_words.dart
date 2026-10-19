import 'dart:convert';

import '../../mail_conventions.dart';

/// Where an RFC 2047 encoded-word is placed.
///
/// The placement decides which ASCII characters may stay unencoded inside a
/// "Q" encoded-word, compare https://tools.ietf.org/html/rfc2047#section-5
enum EncodedWordContext {
  /// Unstructured text such as the `Subject` header (RFC 2047 §5(1)).
  ///
  /// Any printable ASCII character except `=`, `?` and `_` may stay as is.
  text,

  /// A phrase such as the display name of an address (RFC 2047 §5(3)).
  ///
  /// Only letters, digits and `!*+-/` may stay as is: every other character
  /// is an RFC 5322 special (for example `,` `<` `(` `"`) or would be read
  /// as one once the encoded-word is emitted outside a quoted-string.
  phrase,
}

/// Builds RFC 2047 encoded-words.
///
/// Every word carries whole characters and is decodable on its own, is at most
/// [MailConventions.encodedWordMaxLength] characters long, and is separated
/// from the next word by a single space, so header folding can break between
/// words and never inside one.
class EncodedWords {
  EncodedWords._();

  /// The IANA name of the charset used for all encoded-words.
  static const String charset = 'UTF-8';

  static const String _qHead = '=?$charset?Q?';
  static const String _bHead = '=?$charset?B?';
  static const String _tail = '?=';

  /// Encodes the whole [text] as one or more "Q" encoded-words.
  ///
  /// [firstWordMaxLength] limits the total length of the first word, so that
  /// it can share its line with a header name.
  static String encodeQ(
    String text, {
    required EncodedWordContext context,
    int firstWordMaxLength = MailConventions.encodedWordMaxLength,
  }) =>
      _encode(
        text,
        head: _qHead,
        firstWordMaxLength: firstWordMaxLength,
        contentLength: (pieces) => pieces.fold(0, (sum, p) => sum + p.length),
        render: (pieces) => pieces.join(),
        piece: (rune) => _qPiece(rune, context),
      );

  /// Encodes the whole [text] as one or more "B" encoded-words.
  ///
  /// [firstWordMaxLength] limits the total length of the first word, so that
  /// it can share its line with a header name.
  static String encodeB(
    String text, {
    int firstWordMaxLength = MailConventions.encodedWordMaxLength,
  }) =>
      _encode(
        text,
        head: _bHead,
        firstWordMaxLength: firstWordMaxLength,
        contentLength: (pieces) {
          final byteCount = pieces.fold(0, (sum, p) => sum + p.length);

          return ((byteCount + 2) ~/ 3) * 4;
        },
        render: (pieces) =>
            base64.encode([for (final bytes in pieces) ...bytes]),
        piece: (rune) => utf8.encode(String.fromCharCode(rune)),
      );

  /// Encodes the words of the unstructured header [text] that need it.
  ///
  /// The encoded span starts and ends at whitespace, since an encoded-word
  /// must be separated from adjacent text by whitespace (RFC 2047 §5(1)):
  /// `Hello Wörld` becomes `Hello =?UTF-8?Q?W=C3=B6rld?=`, never
  /// `Hello W=?UTF-8?Q?=C3=B6?=rld`. Text that needs no encoding is returned
  /// as is, apart from line breaks, which would start a new header.
  ///
  /// Set [fromStart] to encode the whole [text]. [nameLength] is the length
  /// of the header name, so that the first word fits on the line after it.
  static String encodeHeaderText(
    String text, {
    required bool useBase64,
    int nameLength = 0,
    bool fromStart = false,
  }) {
    final cleaned =
        text.replaceAll(_foldedLineBreaks, '').replaceAll(_lineBreaks, ' ');
    final words = _words.allMatches(cleaned).toList();
    final encodedWords = words.where((w) => _wordNeedsEncoding(w.group(0)!));
    if (encodedWords.isEmpty) {
      return cleaned;
    }
    final start = fromStart ? 0 : encodedWords.first.start;
    final end = fromStart ? cleaned.length : encodedWords.last.end;
    final prefix = cleaned.substring(0, start);
    final lineSpace = MailConventions.textLineMaxLength -
        (nameLength + ': '.length) -
        prefix.length;
    // When the line is nearly full, folding moves the first word to the next
    // line anyway, so it may use the full length there.
    final firstWordMaxLength =
        lineSpace >= 24 ? lineSpace : MailConventions.encodedWordMaxLength;
    final span = cleaned.substring(start, end);
    final encoded = useBase64
        ? encodeB(span, firstWordMaxLength: firstWordMaxLength)
        : encodeQ(
            span,
            context: EncodedWordContext.text,
            firstWordMaxLength: firstWordMaxLength,
          );

    return '$prefix$encoded${cleaned.substring(end)}';
  }

  /// Checks if the [rune] cannot appear unencoded in a header.
  ///
  /// This is the case for anything outside printable 7-bit ASCII, except tab.
  static bool requiresEncoding(int rune) =>
      rune > 126 || (rune < 32 && rune != 9);

  /// Checks if the [text] contains something that looks like an
  /// encoded-word, such as `=?UTF-8?Q?hi?=`.
  ///
  /// Decoders would turn it into other text, and lenient ones do so even
  /// inside a quoted-string or a word, so such text has to be encoded itself.
  static bool containsEncodedWord(String text) =>
      _encodedWordLookalike.hasMatch(text);

  /// A word needs encoding when it has a character that cannot appear in a
  /// header, or when it contains something a decoder would decode.
  static bool _wordNeedsEncoding(String word) =>
      word.runes.any(requiresEncoding) || containsEncodedWord(word);

  static final _encodedWordLookalike =
      RegExp(r'=\?[^?\s]+\?[BbQq]\?[^?\s]*\?=');
  static final _words = RegExp(r'[^ \t]+');
  static final _foldedLineBreaks = RegExp(r'\r\n(?=[ \t])');
  static final _lineBreaks = RegExp(r'\r\n|\r|\n');

  /// Encodes the phrase [text], such as a display name, as encoded-words.
  ///
  /// Uses "Q", which keeps Latin text readable, unless "B" needs fewer words:
  /// for scripts such as Cyrillic or CJK it holds about twice as many
  /// characters per word. Fewer words matter because some decoders, Python's
  /// `email.headerregistry` among them, show a space between adjacent
  /// encoded-words in a phrase although RFC 2047 §6.2 says to drop it.
  static String encodePhrase(String text) {
    final q = encodeQ(text, context: EncodedWordContext.phrase);
    final b = encodeB(text);

    return _wordCount(b) < _wordCount(q) ? b : q;
  }

  static int _wordCount(String encoded) => ' '.allMatches(encoded).length + 1;

  static String _encode<T extends Object>(
    String text, {
    required String head,
    required int firstWordMaxLength,
    required int Function(List<T> pieces) contentLength,
    required String Function(List<T> pieces) render,
    required T Function(int rune) piece,
  }) {
    const maxLength = MailConventions.encodedWordMaxLength;
    const space = 0x20;
    final overhead = head.length + _tail.length;
    // Keep room for at least one character, whatever the caller asked for.
    var maxContentLength =
        (firstWordMaxLength.clamp(overhead + 12, maxLength)) - overhead;
    final words = <String>[];
    var runes = <int>[];
    var pieces = <T>[];
    for (final rune in text.runes) {
      final next = piece(rune);
      while (pieces.isNotEmpty &&
          contentLength([...pieces, next]) > maxContentLength) {
        // End the word after its last space when it has one, so that a
        // decoder that wrongly keeps the space between words does not split
        // a word of the text in two.
        final lastSpace = runes.lastIndexOf(space);
        final cut = lastSpace > 0 ? lastSpace + 1 : pieces.length;
        words.add('$head${render(pieces.sublist(0, cut))}$_tail');
        runes = runes.sublist(cut);
        pieces = pieces.sublist(cut);
        maxContentLength = maxLength - overhead;
      }
      runes.add(rune);
      pieces.add(next);
    }
    if (pieces.isNotEmpty) {
      words.add('$head${render(pieces)}$_tail');
    }

    return words.join(' ');
  }

  static String _qPiece(int rune, EncodedWordContext context) {
    if (rune == 0x20) {
      return '_';
    }
    if (_isQSafe(rune, context)) {
      return String.fromCharCode(rune);
    }
    final buffer = StringBuffer();
    for (final byte in utf8.encode(String.fromCharCode(rune))) {
      buffer
        ..write('=')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }

    return buffer.toString();
  }

  static bool _isQSafe(int rune, EncodedWordContext context) {
    final isLetterOrDigit = (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A);
    if (isLetterOrDigit) {
      return true;
    }
    switch (context) {
      case EncodedWordContext.phrase:
        // ! * + - /
        return rune == 0x21 ||
            rune == 0x2A ||
            rune == 0x2B ||
            rune == 0x2D ||
            rune == 0x2F;
      case EncodedWordContext.text:
        // printable ASCII except = ? _
        return rune > 0x20 &&
            rune < 0x7F &&
            rune != 0x3D &&
            rune != 0x3F &&
            rune != 0x5F;
    }
  }
}

import 'dart:math';

import 'package:mime_dart/mime_dart.dart';
import 'package:test/test.dart';

/// Base64 bodies drop whitespace before decoding. A code-unit loop replaced
/// `replaceAll(RegExp(r'\s'), '')`; it must remove exactly the same
/// characters.
void main() {
  final whitespace = RegExp(r'\s');

  test('removes exactly the code units \\s matches', () {
    for (var unit = 0; unit <= 0xFFFF; unit++) {
      final text = 'a${String.fromCharCode(unit)}b';
      expect(Base64MailCodec.removeWhitespace(text),
          text.replaceAll(whitespace, ''),
          reason: 'U+${unit.toRadixString(16)}');
    }
  });

  test('matches the regular expression on random text', () {
    final random = Random(3);
    const pieces = [
      'QUJD',
      '\r\n',
      ' ',
      '\t',
      ' ',
      ' ',
      '﻿',
      '=',
      'x',
      '😀',
      '\u000b',
      '\u000c'
    ];
    for (var round = 0; round < 20000; round++) {
      final b = StringBuffer();
      for (var i = random.nextInt(30); i > 0; i--) {
        b.write(pieces[random.nextInt(pieces.length)]);
      }
      final text = b.toString();
      expect(Base64MailCodec.removeWhitespace(text),
          text.replaceAll(whitespace, ''));
    }
  });

  test('a wrapped body decodes as before', () {
    const codec = Base64MailCodec();
    final data = List.generate(100000, (i) => i % 256);
    final wrapped = codec.encodeData(data);

    expect(codec.decodeData(wrapped), data);
  });
}

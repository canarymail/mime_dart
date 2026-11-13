import 'dart:math';
import 'dart:typed_data';

import 'package:mime_dart/mime_dart.dart';
import 'package:mime_dart/src/codecs/generated_charset_registry.dart';
import 'package:test/test.dart';

/// What every charset mail decodes must guarantee.
///
/// Quoted-printable is decoded by undoing the escapes for the whole part and
/// decoding the bytes once, so the literal ASCII of the part goes through the
/// charset too. That is only safe when the charset reads ASCII as ASCII and
/// never swallows it, so these hold for every canonical charset name.
void main() {
  final names = {
    ...whatwgCharsetLabels.values,
    ...pythonMimeCharsetAliases.values,
  }.toList()
    ..sort();

  // Decodes [bytes] the way mail does; null for a FormatException, which only
  // a strict pass may throw and MailCodec then retries leniently.
  String? decode(List<int> bytes, String charset) {
    try {
      return MailCodec.decodeAsText(
        Uint8List.fromList(bytes),
        '8bit',
        charset,
      );
    } on FormatException {
      return null;
    }
  }

  // ISO-2022-JP gives SO, SI and ESC their own meaning; UTF-16 is not
  // ASCII-compatible at all.
  const asciiExceptions = <String, Set<int>>{
    'iso-2022-jp': {0x0E, 0x0F, 0x1B},
  };
  const notAsciiCompatible = {'utf-16', 'utf-16le', 'utf-16be'};

  for (final withHandler in [true, false]) {
    final mode = withHandler ? 'with' : 'without';
    group('$mode a diagnostics handler', () {
      setUp(() {
        MailCodec.charsetDiagnosticHandler = withHandler ? (_) {} : null;
      });
      tearDown(() {
        MailCodec.charsetDiagnosticHandler = null;
      });

      for (final charset in names) {
        if (notAsciiCompatible.contains(charset)) {
          continue;
        }
        test('$charset never crashes on any byte', () {
          final random = Random(names.indexOf(charset));
          for (var byte = 0; byte < 256; byte++) {
            expect(() => decode([byte], charset), returnsNormally);
          }
          for (var i = 0; i < 300; i++) {
            final bytes = List.generate(
                1 + random.nextInt(8), (_) => random.nextInt(256));
            expect(() => decode(bytes, charset), returnsNormally,
                reason: '$bytes');
          }
        });

        test('$charset reads ASCII as ASCII', () {
          if (decode([0x41], charset) != 'A') {
            return; // not a decodable label
          }
          final exceptions = asciiExceptions[charset] ?? const <int>{};
          for (var byte = 0; byte < 0x80; byte++) {
            if (exceptions.contains(byte)) {
              continue;
            }
            expect(decode([byte], charset), String.fromCharCode(byte),
                reason: '0x${byte.toRadixString(16)}');
          }
        });

        test('$charset never swallows a line break, tab, space or <', () {
          if (decode([0x41], charset) != 'A') {
            return; // not a decodable label
          }
          const suffix = '\r\n\t <b>';
          // ISO-2022-JP may be left in a JIS mode; ESC ( B returns to ASCII.
          final reset = charset == 'iso-2022-jp'
              ? const [0x1B, 0x28, 0x42]
              : const <int>[];
          final random = Random(1000 + names.indexOf(charset));
          for (var i = 0; i < 300; i++) {
            final prefix = List.generate(
                1 + random.nextInt(6), (_) => random.nextInt(256));
            final decoded =
                decode([...prefix, ...reset, ...suffix.codeUnits], charset);
            if (decoded != null) {
              expect(decoded, endsWith(suffix), reason: '$prefix');
            }
          }
        });
      }
    });
  }
}

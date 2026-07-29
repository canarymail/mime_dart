import 'dart:typed_data';

import 'package:mime_dart/mime_dart.dart';
import 'package:test/test.dart';

Uint8List _message(String charset, List<int> body) => Uint8List.fromList([
      ...'Subject: charset test\r\n'
              'MIME-Version: 1.0\r\n'
              'Content-Type: text/plain; charset="$charset"\r\n'
              'Content-Transfer-Encoding: 8bit\r\n\r\n'
          .codeUnits,
      ...body,
    ]);

String _decode(String charset, List<int> body) =>
    MimeMessage.parseFromData(_message(charset, body))
        .decodeContentText()
        ?.trim() ??
    '';

void main() {
  final diagnostics = <CharsetDiagnostic>[];

  setUp(() {
    diagnostics.clear();
    MailCodec.charsetDiagnosticHandler = diagnostics.add;
  });

  tearDown(() {
    MailCodec.charsetDiagnosticHandler = null;
  });

  group('WHATWG compatibility remaps', () {
    for (final label in [
      'iso-8859-1',
      'latin1',
      'us-ascii',
      'ascii',
      'ISO_8859-1:1987',
    ]) {
      test('$label uses windows-1252 punctuation', () {
        expect(_decode(label, [0x80, 0x91, 0x92, 0x96, 0x97]), '€‘’–—');
      });
    }

    test('iso-8859-9 uses windows-1254', () {
      expect(_decode('iso-8859-9', [0x80, 0xD0, 0xFD]), '€Ğı');
    });

    test('iso-8859-11 uses windows-874', () {
      expect(_decode('iso-8859-11', [0x80, 0xA1, 0xFB]), '€ก๛');
    });
  });

  test('versioned ISO labels resolve exactly', () {
    expect(_decode('iso_8859-2:1987', [0xA1]), 'Ą');
  });

  test('generated Python single-byte codec resolves through MIME aliases', () {
    expect(_decode('ibm437', [0x01, 0x80]), '\u0001Ç');
  });

  group('byte-transport regression set', () {
    final cases = <(String, List<int>, String)>[
      ('windows-1255', [0xF9, 0xEC, 0xE5, 0xED], 'שלום'),
      ('windows-1257', [0xDE, 0xE0, 0x73, 0x69, 0x73], 'Žąsis'),
      ('windows-1258', [0x56, 0x69, 0xEA, 0xF2, 0x74], 'Việt'),
      ('windows-874', [0xE4, 0xB7, 0xC2], 'ไทย'),
      ('cp866', [0x8F, 0xE0, 0xA8, 0xA2, 0xA5, 0xE2], 'Привет'),
      (
        'koi8-t',
        [0xF4, 0xCF, 0x8D, 0xC9, 0xCB, 0xC9, 0xD3, 0xD4, 0xCF, 0xCE],
        'Тоҷикистон',
      ),
      ('mac_roman', [0x63, 0x61, 0x66, 0x8E], 'café'),
      ('mac_cyrillic', [0x8F, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2], 'Привет'),
      ('iso8859_16', [0x52, 0x6F, 0x6D, 0xE2, 0x6E, 0xE3], 'Română'),
    ];

    for (final (label, bytes, expected) in cases) {
      test(label, () {
        expect(_decode(label, bytes), expected);
      });
    }
  });

  test('ISO-2022-JP state changes decode Japanese mail', () {
    expect(
      _decode('iso-2022-jp', [
        0x1B,
        0x24,
        0x42,
        0x46,
        0x7C,
        0x4B,
        0x5C,
        0x38,
        0x6C,
        0x1B,
        0x28,
        0x42,
      ]),
      '日本語',
    );
  });

  test('GB18030 four-byte sequences decode outside GBK', () {
    expect(_decode('gb18030', [0x95, 0x32, 0x82, 0x36]), '𠀀');
  });

  test('Big5 aliases share the upgraded HKSCS mapping', () {
    for (final label in ['big5', 'big5-hkscs', 'cp950']) {
      expect(_decode(label, [0x87, 0x40]), '\u43F0');
    }
  });

  test('UTF-16 and UTF-8-SIG supplemental labels decode', () {
    expect(_decode('utf-16le', [0x41, 0x00, 0x3D, 0xD8, 0xA9, 0xDC]), 'A💩');
    expect(_decode('utf-16be', [0x00, 0x41, 0xD8, 0x3D, 0xDC, 0xA9]), 'A💩');
    expect(_decode('utf-8-sig', [0xEF, 0xBB, 0xBF, 0x41]), 'A');
  });

  test('known unsupported x-user-defined remains observable', () {
    _decode('x-user-defined', [0x80]);

    expect(
      diagnostics,
      contains(
        isA<CharsetDiagnostic>()
            .having(
              (diagnostic) => diagnostic.kind,
              'kind',
              CharsetDiagnosticKind.unsupported,
            )
            .having(
              (diagnostic) => diagnostic.label,
              'label',
              'x-user-defined',
            ),
      ),
    );
  });

  for (final label in [
    'utf-7',
    'iso-2022-kr',
    'iso-2022-cn',
    'iso-2022-cn-ext',
    'hz-gb-2312',
  ]) {
    test('$label is explicitly blocked', () {
      _decode(label, 'ASCII'.codeUnits);

      expect(
        diagnostics,
        contains(
          isA<CharsetDiagnostic>()
              .having(
                (diagnostic) => diagnostic.kind,
                'kind',
                CharsetDiagnosticKind.blocked,
              )
              .having(
                (diagnostic) => diagnostic.label,
                'label',
                label,
              ),
        ),
      );
    });
  }

  test('unknown labels are sanitized and reported without content', () {
    MailCodec.decodeAsText(
      Uint8List.fromList([0x41]),
      '8bit',
      'evil\r\nInjected: value',
    );

    expect(diagnostics.single.kind, CharsetDiagnosticKind.unknown);
    expect(diagnostics.single.label, isNot(contains('\r')));
    expect(diagnostics.single.label, isNot(contains('\n')));
    expect(diagnostics.single.label.length, lessThanOrEqualTo(80));
  });
}

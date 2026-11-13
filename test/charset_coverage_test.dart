import 'dart:convert';
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

  group('quoted-printable', () {
    String decodeQp(String charset, String body) => MimeMessage.parseFromData(
          Uint8List.fromList([
            ...'Subject: qp test\r\n'
                    'MIME-Version: 1.0\r\n'
                    'Content-Type: text/html; charset="$charset"\r\n'
                    'Content-Transfer-Encoding: quoted-printable\r\n\r\n'
                .codeUnits,
            ...body.codeUnits,
          ]),
        ).decodeTextHtmlPart()!.trim();

    // Each case runs with and without a diagnostics handler: without one,
    // MailCodec decodes with the lenient codec only.
    void bothModes(String name, void Function() body) {
      for (final withHandler in [true, false]) {
        test('$name ${withHandler ? 'with' : 'without'} a diagnostics handler',
            () {
          if (!withHandler) {
            MailCodec.charsetDiagnosticHandler = null;
          }
          body();
        });
      }
    }

    group('valid input decodes the whole part with its charset', () {
      bothModes('ISO-2022-JP with only ESC escaped', () {
        expect(
          decodeQp('iso-2022-jp', r'<p>=1B$BF|K\=1B(B=1B$B8l=1B(B</p>'),
          '<p>日本語</p>',
        );
      });

      bothModes('ISO-2022-JP run split by a soft line break', () {
        expect(
          decodeQp('iso-2022-jp', '=1B\$BF|=\r\nK\\8l=1B(B'),
          '日本語',
        );
      });

      // Senders escape only bytes >= 0x80, so a trail byte in the ASCII
      // range stays literal and splits the character across an escape run.
      for (final (charset, body, expected) in [
        ('shift_jis', r'=95\=8E=A6', '表示'),
        ('gbk', '=81@', '丂'),
        ('gb18030', '=81@', '丂'),
        ('big5', r'=A5\=AF=E0', '功能'),
      ]) {
        bothModes('$charset trail byte left literal', () {
          expect(decodeQp(charset, body), expected);
        });
      }

      // Strict decoding fails on the unmapped `"/`; the lenient retry must
      // decode the whole part rather than fall back to per-run decoding,
      // which left the escapes in and reported it as supported.
      bothModes('ISO-2022-JP with ESC left literal and one unmapped pair', () {
        expect(
          decodeQp('iso-2022-jp', '\x1B\$BF|K\\8l"/\x1B(B'),
          '日本語�',
        );
      });

      bothModes('the same part ending in a bare =', () {
        expect(
          decodeQp('iso-2022-jp', '\x1B\$BF|K\\8l"/\x1B(B ='),
          '日本語�',
        );
      });

      bothModes('UTF-8 escapes and literal ASCII', () {
        expect(decodeQp('utf-8', 'caf=C3=A9 =3D ok'), 'café = ok');
      });

      bothModes('an unparsable escape keeps the rest', () {
        expect(decodeQp('utf-8', 'caf=C3=A9 =C3=ZZ ok'), 'café �ZZ ok');
      });

      bothModes('an = before a sign or space is not an escape', () {
        // int.tryParse would read ' 1' as 1, '-1' as -1 and ' A' as 10.
        expect(decodeQp('utf-8', 'a= 1b=-1c x=C3= Ay'), 'a 1b-1c x� Ay');
      });
    });

    // Whole-part decoding sends the literal ASCII of a part through the
    // charset, so a charset that misreads ASCII breaks valid QP. Each of
    // these decoded right before whole-part decoding.
    group('literal ASCII goes through the charset intact', () {
      bothModes('cp850 keeps line breaks and tabs', () {
        expect(
          decodeQp('cp850', 'Gr=81=E1e\r\nZeile 2\tEnde'),
          'Grüße\r\nZeile 2\tEnde',
        );
        expect(decodeQp('ibm850', '<a\r\nhref=3D"x">'), '<a\r\nhref="x">');
      });

      bothModes('a literal NUL in a single-byte charset', () {
        for (final charset in ['iso-8859-1', 'windows-1250', 'koi8-r']) {
          expect(
            decodeQp(charset, '<p>caf=E9\u0000</p>'),
            charset == 'koi8-r'
                ? '<p>caf\u0418\u0000</p>'
                : '<p>café\u0000</p>',
            reason: charset,
          );
        }
      });

      bothModes('gbk keeps the ASCII after a bad byte, and 0x80 is €', () {
        expect(decodeQp('gb2312', 'Price: =80100 only'), 'Price: €100 only');
        expect(decodeQp('gbk', 'x=FF<b>'), 'x�<b>');
      });
    });

    // A bad escape drops the `=` and keeps the two characters after it, as
    // before (which threw instead on a trailing `=1`).
    group('an = that is not an escape', () {
      for (final (body, expected) in [
        ('if (a == b && c === d)', 'if (a = b && c == d)'),
        ('?t=YWJjZA==&u=1', '?tYWJjZA=&u1'),
        ('x=4=41y', 'x4=41y'),
      ]) {
        bothModes(body, () {
          expect(decodeQp('utf-8', body), expected);
        });
      }

      test('a _ after it in a header stays an underscore', () {
        expect(MailCodec.decodeHeader('=?utf-8?Q?a=_b?='), 'a_b');
      });
    });

    // Raw 8-bit bytes are not valid quoted-printable, and whether they are
    // UTF-8 or Latin-1 can only be guessed, so these decode exactly as they
    // did before whole-part decoding. The expected values are that output.
    group('raw 8-bit or Unicode text decodes as before', () {
      for (final (body, expected) in [
        ('café =C3=A9', 'café é'),
        ('café =C3=28', 'café �('),
        (
          'Noël fermé » café',
          'Noël fermé » café',
        ),
        (
          String.fromCharCodes(utf8.encode('日本 a=3Db')),
          '${String.fromCharCodes(utf8.encode('日本'))} a=b',
        ),
      ]) {
        bothModes('${jsonEncode(body)} in a UTF-8 part', () {
          expect(decodeQp('utf-8', body), expected);
        });
      }

      test('lenient direct decodeText', () {
        expect(
          MailCodec.quotedPrintable
              .decodeText('café =C3=A9', MailCodec.encodingUtf8),
          'café é',
        );
      });

      test('text that is already Unicode', () {
        for (final (text, expected) in [
          ('日本 caf=C3=A9', '日本 café'),
          ('Grüße Ã©té', 'Grüße Ã©té'),
        ]) {
          expect(
            MailCodec.quotedPrintable.decodeText(text, MailCodec.encodingUtf8),
            expected,
          );
        }
      });
    });
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

  group('UTF-16 BOM handling', () {
    for (final label in [
      'utf-16',
      'unicode',
      'ucs-2',
      'csunicode',
      'iso-10646-ucs-2',
    ]) {
      test('$label sniffs either byte order and consumes the BOM', () {
        expect(_decode(label, [0xFE, 0xFF, 0x00, 0x41]), 'A');
        expect(_decode(label, [0xFF, 0xFE, 0x41, 0x00]), 'A');
        expect(_decode(label, [0x41, 0x00]), 'A');
      });
    }

    test('explicit endian labels consume and honor a BOM', () {
      expect(_decode('utf-16le', [0xFF, 0xFE, 0x41, 0x00]), 'A');
      expect(_decode('utf-16le', [0xFE, 0xFF, 0x00, 0x41]), 'A');
      expect(_decode('utf-16be', [0xFE, 0xFF, 0x00, 0x41]), 'A');
      expect(_decode('utf-16be', [0xFF, 0xFE, 0x41, 0x00]), 'A');
    });
  });

  test('valid UTF-8 U+FFFD is supported rather than a decode failure', () {
    expect(_decode('utf-8', [0xEF, 0xBF, 0xBD]), '\uFFFD');
    expect(diagnostics.single.kind, CharsetDiagnosticKind.supported);
    expect(diagnostics.single.replacementCount, 0);
  });

  test('malformed input uses lenient output and reports decode failure', () {
    expect(_decode('utf-8', [0xFF]), '\uFFFD');
    expect(diagnostics.single.kind, CharsetDiagnosticKind.decodeFailure);
    expect(diagnostics.single.replacementCount, 1);
    expect(
      CharsetDiagnostic.fromMap(diagnostics.single.toMap()).replacementCount,
      1,
    );
  });

  test('malformed quoted-printable input reports decode failure', () {
    expect(
      MailCodec.decodeAnyText('=FF', 'quoted-printable', 'utf-8'),
      '\uFFFD',
    );
    expect(diagnostics.single.kind, CharsetDiagnosticKind.decodeFailure);
    expect(diagnostics.single.replacementCount, 1);
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

  for (final label in [
    'x-utf-7',
    'x_utf_7',
    'x-iso-2022-kr',
    'x_hz-gb-2312',
  ]) {
    test('$label remains blocked after compatibility normalization', () {
      _decode(label, 'ASCII'.codeUnits);
      expect(diagnostics.single.kind, CharsetDiagnosticKind.blocked);
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

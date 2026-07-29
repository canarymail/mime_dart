import 'dart:typed_data';

import 'package:mime_dart/mime_dart.dart';
import 'package:test/test.dart';

/// 日本語 in Shift_JIS.
final _shiftJisBody = [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA];

Uint8List _message(String charset, List<int> body, {String cte = '8bit'}) =>
    Uint8List.fromList([
      ...'Subject: t\r\n'
              'MIME-Version: 1.0\r\n'
              'Content-Type: text/plain; charset=$charset\r\n'
              'Content-Transfer-Encoding: $cte\r\n\r\n'
          .codeUnits,
      ...body,
    ]);

void main() {
  group('Shift_JIS messages decode', () {
    test('with the canonical label', () {
      final mime = MimeMessage.parseFromData(_message('Shift_JIS', _shiftJisBody));

      expect(mime.decodeContentText()?.trim(), '日本語');
    });

    // Before charset-name normalisation only the exact canonical spelling
    // resolved; every other real-world label fell through to the UTF-8 fallback
    // and produced replacement characters.
    for (final label in [
      'shift_jis',
      'SHIFT_JIS',
      'shift-jis',
      'Shift-JIS',
      'sjis',
      'x-sjis',
      'csShiftJIS',
      'ms_kanji',
      'windows-31j',
      'cp932',
      ' shift_jis ',
    ]) {
      test('with the label "$label"', () {
        final mime = MimeMessage.parseFromData(_message(label, _shiftJisBody));

        expect(mime.decodeContentText()?.trim(), '日本語',
            reason: 'label "$label" should resolve to Shift_JIS');
      });
    }

    test('including cp932 extensions real mail carries', () {
      // (1) and the Takahashi surname kanji — absent from strict JIS X 0208.
      final mime = MimeMessage.parseFromData(
          _message('Shift_JIS', [0x87, 0x40, 0xFB, 0xFC]));

      expect(mime.decodeContentText()?.trim(), '①髙');
    });
  });

  group('other CJK charsets decode', () {
    test('EUC-JP', () {
      final mime = MimeMessage.parseFromData(
          _message('euc-jp', [0xC6, 0xFC, 0xCB, 0xDC, 0xB8, 0xEC]));

      expect(mime.decodeContentText()?.trim(), '日本語');
    });

    test('EUC-KR', () {
      final mime = MimeMessage.parseFromData(
          _message('euc-kr', [0xC7, 0xD1, 0xB1, 0xDB]));

      expect(mime.decodeContentText()?.trim(), '한글');
    });

    test('EUC-KR under the ks_c_5601-1987 label Outlook emits', () {
      final mime = MimeMessage.parseFromData(
          _message('ks_c_5601-1987', [0xC7, 0xD1, 0xB1, 0xDB]));

      expect(mime.decodeContentText()?.trim(), '한글');
    });
  });

  group('previously-missing spellings of supported charsets', () {
    // These charsets were always supported; only their labels failed to
    // resolve, so the messages decoded as UTF-8 and came out as mojibake.
    for (final label in ['latin1', 'ISO_8859-1', 'iso-ir-100', 'csISOLatin1']) {
      test('"$label" resolves to ISO-8859-1', () {
        // café in ISO-8859-1
        final mime = MimeMessage.parseFromData(
            _message(label, [0x63, 0x61, 0x66, 0xE9]));

        expect(mime.decodeContentText()?.trim(), 'café');
      });
    }
  });

  group('base64 CJK', () {
    test('Shift_JIS in base64 decodes — the case byte transport exposed', () {
      // Base64 payloads were never affected by the transport bug, but they were
      // undecodable for want of the codec itself.
      final mime = MimeMessage.parseFromData(
          _message('Shift_JIS', 'k/qWe4zq'.codeUnits, cte: 'base64'));

      expect(mime.decodeContentText()?.trim(), '日本語');
    });
  });
}

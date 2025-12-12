import 'dart:convert';

import 'package:mime_dart/src/codecs/mail_codec.dart';
import 'package:test/test.dart';
// cSpell:disable

void main() {
  group('Base64 decoding', () {
    test('encoding.iso-8859-1 base64 directly repeated', () {
      const input = '=?ISO-8859-1?B?SWYgeW91IGNhbiByZWFkIHRoaXMgeW8=?==?ISO-'
          '8859-2?B?dSB1bmRlcnN0YW5kIHRoZSBleGFtcGxlLg==?=';
      expect(
        MailCodec.decodeHeader(input),
        'If you can read this you understand the example.',
      );
    });

    test('encoding.UTF-8.Base64 with non-devidable-by-four base64 text', () {
      expect(MailCodec.base64.decodeText('8J+UkA', utf8), '🔐');
      const input = '=?utf-8?B?8J+UkA?= New Access Request - local.name';
      expect(
        MailCodec.decodeHeader(input),
        '🔐 New Access Request - local.name',
      );
    });

    test('encoding.US-ASCII.Base64', () {
      var input = '=?US-ASCII?B?S2VpdGggTW9vcmU?= <moore@cs.utk.edu>';
      expect(MailCodec.decodeHeader(input), 'Keith Moore <moore@cs.utk.edu>');
      input = '=?US-ASCII?B?S2VpdGggTW9vcmU=?= <moore@cs.utk.edu>';
      expect(MailCodec.decodeHeader(input), 'Keith Moore <moore@cs.utk.edu>');
    });

    test('Base64 with embedded spaces (RFC 2045 compliant)', () {
      // Test case 1: Simple base64 with spaces
      const base64WithSpaces = 'SGVs bG8g V29y bGQ=';
      expect(
        MailCodec.base64.decodeText(base64WithSpaces, utf8),
        'Hello World',
      );

      // Test case 2: Base64 with line breaks and spaces
      const base64WithLineBreaksAndSpaces = 'SGVs bG8g\r\nV29y bGQ=';
      expect(
        MailCodec.base64.decodeText(base64WithLineBreaksAndSpaces, utf8),
        'Hello World',
      );

      // Test case 3: Base64 with tabs
      const base64WithTabs = 'SGVs\tbG8g\tV29y\tbGQ=';
      expect(
        MailCodec.base64.decodeText(base64WithTabs, utf8),
        'Hello World',
      );

      // Test case 4: Base64 with mixed whitespace
      const base64WithMixedWhitespace = 'SGVs bG8g \r\n V29y\tbGQ=';
      expect(
        MailCodec.base64.decodeText(base64WithMixedWhitespace, utf8),
        'Hello World',
      );
    });
  });

  group('Base64 encoding', () {
    test('encodeHeader.base64 with ASCII input', () {
      const input = 'Hello World';
      expect(MailCodec.base64.encodeHeader(input), 'Hello World');
    });
    test('encodeHeader.base64 with UTF8 input', () {
      const input = 'Hello Wörld';
      expect(MailCodec.base64.encodeHeader(input), 'Hello W=?utf8?B?w7Y=?=rld');
      // counter test:
      expect(
        MailCodec.decodeHeader('Hello W=?utf8?B?w7Y=?=rld'),
        'Hello Wörld',
      );
    });
  });
}

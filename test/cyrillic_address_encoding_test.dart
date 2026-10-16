import 'package:mime_dart/mime_dart.dart';
import 'package:test/test.dart';

void main() {
  group('non-ASCII address display-name encoding', () {
    test('Cyrillic display name is a bare RFC 2047 encoded-word, not quoted',
        () {
      final addr = MailAddress('Виктор', 'victor@spectrite.ru');
      final encoded = addr.encode();

      // The encoded-word must not be wrapped in a quoted-string (RFC 2047 §5),
      // or strict clients leave it undecoded.
      expect(encoded,
          '=?utf8?Q?=D0=92=D0=B8=D0=BA=D1=82=D0=BE=D1=80?= <victor@spectrite.ru>');
      expect(encoded, isNot(startsWith('"')));
    });

    test('pure ASCII display name is still quoted', () {
      final addr = MailAddress('Victor', 'victor@spectrite.ru');
      expect(addr.encode(), '"Victor" <victor@spectrite.ru>');
    });

    test('To/Cc display names round-trip back to the originals', () {
      final builder = MessageBuilder()
        ..from = [MailAddress('Me', 'me@example.com')]
        ..to = [MailAddress('Виктор', 'victor@spectrite.ru')]
        ..cc = [MailAddress('Анна', 'anna@spectrite.ru')]
        ..text = 'hello';
      final mime = builder.buildMimeMessage();
      final reparsed = MimeMessage.parseFromText(mime.renderMessage());
      expect(reparsed.to!.first.personalName, 'Виктор');
      expect(reparsed.cc!.first.personalName, 'Анна');
    });
  });
}

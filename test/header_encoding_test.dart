import 'package:mime_dart/mime_dart.dart';
import 'package:test/test.dart';

/// Matches one "Q" encoded-word and captures its encoded text.
final _qWord = RegExp(r'=\?UTF-8\?Q\?([^?]*)\?=');

/// Matches any encoded-word.
final _anyWord = RegExp(r'=\?[^?]+\?[QqBb]\?[^?]*\?=');

/// The characters a "Q" encoded-word in a phrase may carry (RFC 2047 §5(3)).
final _phraseSafe = RegExp(r'^[A-Za-z0-9!*+\-/=_]*$');

/// Renders a message from [builder] and parses it again.
MimeMessage _roundTrip(MessageBuilder builder) =>
    MimeMessage.parseFromText(builder.buildMimeMessage().renderMessage());

/// The header block of the message rendered from [builder].
String _renderedHeaders(MessageBuilder builder) =>
    builder.buildMimeMessage().renderMessage().split('\r\n\r\n').first;

void main() {
  group('display names', () {
    test('a non-ASCII name is a bare encoded-word, not quoted', () {
      const inputAddress = MailAddress('Виктор', 'victor@example.com');

      final actualEncoded = inputAddress.encode();

      // An encoded-word inside a quoted-string is not decoded by strict
      // clients (RFC 2047 §5).
      expect(
        actualEncoded,
        '=?UTF-8?Q?=D0=92=D0=B8=D0=BA=D1=82=D0=BE=D1=80?= <victor@example.com>',
      );
    });

    test('an ASCII name is a quoted-string', () {
      const inputAddress = MailAddress('Victor', 'victor@example.com');

      expect(inputAddress.encode(), '"Victor" <victor@example.com>');
    });

    test('an ASCII name escapes quotes and backslashes', () {
      const inputAddress = MailAddress(r'Foo "Bar" \Baz', 'foo@example.com');

      expect(
        inputAddress.encode(),
        r'"Foo \"Bar\" \\Baz" <foo@example.com>',
      );
    });

    test('RFC 5322 specials in a non-ASCII name are encoded', () {
      const inputNames = [
        'Müller, Hans',
        'Jörg; Team',
        'Zoë <boss>',
        'Zoë (work)',
        'Jörg "JJ" Smith',
        'Zoë @ Acme: Sales',
        r'Dr. Müller [EU] \ HQ',
      ];
      for (final inputName in inputNames) {
        final actualEncoded = MailAddress(inputName, 'a@example.com').encode();

        final actualWords = _qWord.allMatches(actualEncoded).toList();
        expect(actualWords, isNotEmpty, reason: inputName);
        for (final word in actualWords) {
          expect(word.group(1), matches(_phraseSafe), reason: inputName);
        }
        expect(actualEncoded, endsWith(' <a@example.com>'), reason: inputName);
      }
    });

    test('an emoji name is a terminated encoded-word', () {
      const inputAddress = MailAddress('Anna 😀', 'anna@example.com');

      expect(
        inputAddress.encode(),
        '=?UTF-8?Q?Anna_=F0=9F=98=80?= <anna@example.com>',
      );
    });

    test('a long name is split into words of at most 75 characters', () {
      const inputAddress = MailAddress(
        'Виктор Александрович Константинопольский Преображенский',
        'v@example.com',
      );

      final actualEncoded = inputAddress.encode();

      final actualWords = _anyWord.allMatches(actualEncoded).toList();
      expect(actualWords.length, greaterThan(1));
      for (final word in actualWords) {
        expect(word.group(0)!.length, lessThanOrEqualTo(75));
      }
      // Words end after a space of the name, never inside one of its words
      // (unless a single word is too long for an encoded-word).
      final actualParts =
          actualWords.map((w) => MailCodec.decodeHeader(w.group(0))!).toList();
      for (final part in actualParts.take(actualParts.length - 1)) {
        expect(part, endsWith(' '));
      }
      expect(
        actualParts.join(),
        'Виктор Александрович Константинопольский Преображенский',
      );
    });

    test('a name that needs fewer words in B is B-encoded', () {
      // In Q this name needs two words; some decoders show a space between
      // them.
      const inputAddress = MailAddress('Александр Иванов', 'a@example.com');

      expect(
        inputAddress.encode(),
        '=?UTF-8?B?0JDQu9C10LrRgdCw0L3QtNGAINCY0LLQsNC90L7Qsg==?= '
        '<a@example.com>',
      );
    });

    test('a line break in a name cannot start a new header', () {
      const inputNames = ['Foo\r\nBcc: evil@example.com', 'Jörg\nBcc: x@y.z'];
      for (final inputName in inputNames) {
        final actualEncoded = MailAddress(inputName, 'a@example.com').encode();

        expect(actualEncoded, isNot(contains('\r')), reason: inputName);
        expect(actualEncoded, isNot(contains('\n')), reason: inputName);
      }
      expect(
        const MailAddress('Foo\r\nBar', 'a@example.com').encode(),
        '"Foo Bar" <a@example.com>',
      );
    });

    test('a name of only whitespace leaves the bare address', () {
      const inputAddress = MailAddress(' \r\n ', 'a@example.com');

      expect(inputAddress.encode(), 'a@example.com');
    });
  });

  group('email addresses', () {
    test('control characters and angle brackets are removed', () {
      const inputAddress =
          MailAddress('Me', '<me@example.com>\r\nBcc: evil@example.com');

      expect(
        inputAddress.encode(),
        '"Me" <me@example.comBcc: evil@example.com>',
      );
      expect(
        const MailAddress(null, ' me@example.com\r\n').encode(),
        'me@example.com',
      );
    });

    test('a non-ASCII address is kept as UTF-8, never encoded', () {
      // RFC 2047 forbids encoded-words in an addr-spec; RFC 6532 allows UTF-8.
      const inputAddress = MailAddress('Коля', 'коля@пример.рф');

      final actualEncoded = inputAddress.encode();

      expect(actualEncoded, endsWith(' <коля@пример.рф>'));
    });
  });

  group('address headers', () {
    const inputNames = [
      'Виктор',
      'Александр Иванов',
      'Константин Константинопольский-Преображенский',
      'Müller, Hans',
      'Zoë <boss>',
      'Jörg "JJ" Smith',
      'Anna 😀',
      'Jürgen aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      r'Plain "ASCII", \Name',
    ];

    test('names in From, Sender, To, Cc and Bcc round-trip', () {
      for (final inputName in inputNames) {
        final inputAddress = MailAddress(inputName, 'person@example.com');
        final inputBuilder = MessageBuilder()
          ..from = [inputAddress]
          ..sender = inputAddress
          ..to = [
            inputAddress,
            const MailAddress('Second', 'second@example.com')
          ]
          ..cc = [inputAddress]
          ..bcc = [inputAddress]
          ..text = 'hello';

        final actualMessage = _roundTrip(inputBuilder);

        for (final actual in [
          actualMessage.from,
          [actualMessage.sender!],
          actualMessage.to,
          actualMessage.cc,
          actualMessage.bcc,
        ]) {
          expect(actual!.first.personalName, inputName, reason: inputName);
          expect(actual.first.email, 'person@example.com', reason: inputName);
        }
        expect(actualMessage.to!.length, 2, reason: inputName);
        expect(actualMessage.to![1].email, 'second@example.com');
      }
    });

    test('folding never splits an encoded-word', () {
      for (final inputName in inputNames) {
        final inputAddress = MailAddress(inputName, 'person@example.com');
        final inputBuilder = MessageBuilder()
          ..from = [inputAddress]
          ..sender = inputAddress
          ..to = [inputAddress]
          ..text = 'hello';

        final actualHeaders = _renderedHeaders(inputBuilder);

        for (final line in actualHeaders.split('\r\n')) {
          final lineWithoutWords = line.replaceAll(_anyWord, '');
          expect(lineWithoutWords, isNot(contains('=?')), reason: line);
          expect(lineWithoutWords, isNot(contains('?=')), reason: line);
        }
        expect(actualHeaders, isNot(contains('"=?')));
      }
    });
  });

  group('subject', () {
    const inputSubjects = [
      'Hello Wörld',
      'Re: Привет, мир!',
      'Встреча в понедельник: повестка, материалы и вопросы к обсуждению',
      'Party 🎉 tonight',
      '[JIRA-123]Fix the (very) long ASCII subject line that needs folding now',
      'Price: 10 € (net) = 12 € _gross_?',
      'Not encoded: =?utf-8?Q?abc?=',
    ];

    test('subjects round-trip with Q and B encoding', () {
      for (final inputEncoding in [HeaderEncoding.Q, HeaderEncoding.B]) {
        for (final inputSubject in inputSubjects) {
          final inputBuilder = MessageBuilder()
            ..from = [const MailAddress('Me', 'me@example.com')]
            ..to = [const MailAddress('You', 'you@example.com')]
            ..subject = inputSubject
            ..subjectEncoding = inputEncoding
            ..text = 'hello';

          final actualSubject = _roundTrip(inputBuilder).decodeSubject();

          expect(actualSubject, inputSubject, reason: '$inputEncoding');
        }
      }
    });

    test('only whole words are encoded', () {
      expect(
        MailCodec.quotedPrintable.encodeHeader('Re: Hello Wörld today'),
        'Re: Hello =?UTF-8?Q?W=C3=B6rld?= today',
      );
    });

    test('every encoded-word is at most 75 characters', () {
      for (final inputSubject in inputSubjects) {
        final actualEncoded = MailCodec.quotedPrintable
            .encodeHeader(inputSubject, nameLength: 'Subject'.length);

        for (final word in _anyWord.allMatches(actualEncoded)) {
          expect(word.group(0)!.length, lessThanOrEqualTo(75));
        }
      }
    });

    test('B encoded-words decode on their own', () {
      final actualEncoded = MailCodec.base64.encodeHeader(
        'Встреча в понедельник: повестка, материалы и вопросы к обсуждению',
      );

      final actualWords = _anyWord.allMatches(actualEncoded).toList();
      expect(actualWords.length, greaterThan(1));
      final actualDecoded =
          actualWords.map((w) => MailCodec.decodeHeader(w.group(0))).join();
      expect(
        actualDecoded,
        'Встреча в понедельник: повестка, материалы и вопросы к обсуждению',
      );
    });

    test('a line break in a subject cannot start a new header', () {
      final inputBuilder = MessageBuilder()
        ..from = [const MailAddress('Me', 'me@example.com')]
        ..to = [const MailAddress('You', 'you@example.com')]
        ..subject = 'Hello\r\nBcc: evil@example.com'
        ..text = 'hello';

      final actualMessage = _roundTrip(inputBuilder);

      expect(actualMessage.decodeSubject(), 'Hello Bcc: evil@example.com');
      expect(actualMessage.hasHeader('bcc'), isFalse);
    });
  });

  group('attachment filenames', () {
    test('a non-ASCII filename is encoded whole', () {
      final inputHeader = ContentDispositionHeader.from(
        ContentDisposition.attachment,
        filename: 'Bericht Über 2026.pdf',
      );

      final actualRendered = inputHeader.render();

      // Partly encoded text inside a quoted parameter is not decoded by
      // strict clients; the whole value is one or more encoded-words.
      final actualValue =
          RegExp('filename="([^"]*)"').firstMatch(actualRendered)!.group(1)!;
      expect(actualValue.replaceAll(_anyWord, '').trim(), isEmpty);
      expect(MailCodec.decodeHeader(actualValue), 'Bericht Über 2026.pdf');
    });

    test('an ASCII filename is not encoded', () {
      final inputHeader = ContentDispositionHeader.from(
        ContentDisposition.attachment,
        filename: 'report 2026.pdf',
      );

      expect(inputHeader.render(), contains('filename="report 2026.pdf"'));
    });
  });
}

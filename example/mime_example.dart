import 'dart:typed_data';
import 'package:mime_dart/mime_dart.dart';

void main() async {
  print('MIME Dart Example\n');

  await parsingExample();
  print('\n---\n');
  await buildingExample();
  print('\n---\n');
  await attachmentExample();
}

/// Example: Parse a MIME message
Future<void> parsingExample() async {
  print('Parsing Example:');

  final mimeText = '''From: sender@example.com
To: recipient@example.com
Subject: Hello World
Content-Type: text/plain; charset=utf-8

This is the message body.
''';

  final message = MimeMessage.parseFromText(mimeText);

  print('From: ${message.from}');
  print('To: ${message.to}');
  print('Subject: ${message.decodeSubject()}');
  print('Body: ${message.decodeTextPlainPart()}');
}

/// Example: Build a simple MIME message
Future<void> buildingExample() async {
  print('Building Example:');

  final builder = MessageBuilder.prepareMultipartAlternativeMessage(
    plainText: 'Hello world!',
    htmlText: '<p>Hello <b>world</b>!</p>',
  )
    ..from = [MailAddress('Sender Name', 'sender@example.com')]
    ..to = [
      MailAddress('Recipient Name', 'recipient@example.com'),
      MailAddress('Another Recipient', 'other@example.com')
    ]
    ..subject = 'My first message';

  final mimeMessage = builder.buildMimeMessage();
  print('Generated MIME message:');
  print(mimeMessage.renderMessage());
}

/// Example: Build a message with attachment
Future<void> attachmentExample() async {
  print('Attachment Example:');

  final builder = MessageBuilder()
    ..from = [MailAddress('Sender Name', 'sender@example.com')]
    ..to = [MailAddress('Recipient Name', 'recipient@example.com')]
    ..subject = 'Message with attachment'
    ..addTextPlain('Please find the document attached.');

  // Add a text file as attachment
  builder.addBinary(
    Uint8List.fromList('Hello from attachment!'.codeUnits),
    MediaType.fromSubtype(MediaSubtype.textPlain),
    filename: 'hello.txt',
  );

  final mimeMessage = builder.buildMimeMessage();
  print('Message with attachment:');
  print(mimeMessage.renderMessage());

  // Parse and extract attachment
  if (mimeMessage.hasAttachments()) {
    final attachments = mimeMessage.findContentInfo(
      disposition: ContentDisposition.attachment,
    );
    print('\nFound ${attachments.length} attachment(s):');
    for (final attachment in attachments) {
      print('- ${attachment.fileName} (${attachment.size} bytes)');
    }
  }
}

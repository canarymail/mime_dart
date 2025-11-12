# mime_dart

Pure Dart MIME message parser and builder for email developers.

Available under the commercial friendly 
[MPL Mozilla Public License 2.0](https://www.mozilla.org/en-US/MPL/).

## Installation

Add this dependency to your pubspec.yaml file:

```yaml
dependencies:
  mime_dart: ^1.0.0
```

## Features

- ✅ Parse MIME/email messages
- ✅ Build MIME/email messages with `MessageBuilder`
- ✅ Support for various encodings (7bit, 8bit, quoted-printable, base64)
- ✅ Support for attachments
- ✅ Support for multipart messages (mixed, alternative, etc.)
- ✅ Email address parsing and formatting
- ✅ Header encoding/decoding
- ✅ Character set conversion via [enough_convert](https://pub.dev/packages/enough_convert)
- ✅ **Web platform support** - works on all platforms including web browsers

## API Documentation

Check out the full API documentation at https://pub.dev/documentation/mime_dart/latest/

## Usage Examples

### Parsing MIME Messages

```dart
import 'package:mime_dart/mime_dart.dart';

void main() {
  // Parse a MIME message from text
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
```

### Building Simple Messages

```dart
import 'package:mime_dart/mime_dart.dart';

void main() {
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
  print(mimeMessage.renderMessage());
}
```

### Building Messages with Attachments (Native Platforms)

```dart
import 'dart:io';
import 'package:mime_dart/mime_dart.dart';

Future<void> main() async {
  final builder = MessageBuilder()
    ..from = [MailAddress('Sender Name', 'sender@example.com')]
    ..to = [MailAddress('Recipient Name', 'recipient@example.com')]
    ..subject = 'Message with attachment'
    ..addMultipartAlternative(
      plainText: 'Please find the document attached.',
      htmlText: '<p>Please find the document <b>attached</b>.</p>',
    );
  
  // Add file attachment (native platforms only)
  final file = File('document.pdf');
  await builder.addFile(file, MediaSubtype.applicationPdf.mediaType);
  
  final mimeMessage = builder.buildMimeMessage();
  print(mimeMessage.renderMessage());
}
```

### Building Messages with Attachments (Web-Compatible)

For web platform compatibility, use `addBinaryData()` or `addBinary()` instead of `addFile()`:

```dart
import 'dart:typed_data';
import 'package:mime_dart/mime_dart.dart';

void main() {
  final builder = MessageBuilder()
    ..from = [MailAddress('Sender Name', 'sender@example.com')]
    ..to = [MailAddress('Recipient Name', 'recipient@example.com')]
    ..subject = 'Message with attachment'
    ..addMultipartAlternative(
      plainText: 'Please find the document attached.',
      htmlText: '<p>Please find the document <b>attached</b>.</p>',
    );
  
  // Add binary data attachment (works on all platforms including web)
  final pdfBytes = Uint8List.fromList([...]); // your PDF data
  builder.addBinaryData(
    pdfBytes,
    'document.pdf',
    MediaSubtype.applicationPdf.mediaType,
  );
  
  final mimeMessage = builder.buildMimeMessage();
  print(mimeMessage.renderMessage());
}
```

### Working with Email Addresses

```dart
import 'package:mime_dart/mime_dart.dart';

void main() {
  // Create email addresses
  final address = MailAddress('Personal Name', 'email@example.com');
  print(address.encode()); // "Personal Name" <email@example.com>
  
  // Parse email addresses from text
  final addresses = [
    MailAddress.parse('"John Doe" <john@example.com>')!,
    MailAddress.parse('jane@example.com')!,
  ];
  
  for (final addr in addresses) {
    print('Name: ${addr.personalName}, Email: ${addr.email}');
  }
}
```

### Handling Attachments

```dart
import 'package:mime_dart/mime_dart.dart';

void main() {
  final mimeText = '''[Your MIME message with attachments]''';
  final message = MimeMessage.parseFromText(mimeText);
  
  // Check for attachments
  if (message.hasAttachments()) {
    final attachments = message.findContentInfo(
      disposition: ContentDisposition.attachment,
    );
    
    for (final attachment in attachments) {
      print('Attachment: ${attachment.fileName}');
      print('Size: ${attachment.size} bytes');
      print('Content-Type: ${attachment.contentType?.mediaType}');
      
      // Decode attachment data (works on all platforms)
      final data = attachment.part?.decodeContentBinary();
      if (data != null) {
        // On web: use the bytes directly (e.g., create a download link)
        // On native: save to file using dart:io
        print('Decoded ${data.length} bytes');
      }
    }
  }
}
```

### Multipart Messages

```dart
import 'package:mime_dart/mime_dart.dart';

void main() {
  // Build a complex multipart message
  final builder = MessageBuilder()
    ..from = [MailAddress('sender@example.com')]
    ..to = [MailAddress('recipient@example.com')]
    ..subject = 'Multipart Example';
  
  // Add alternative plain text and HTML
  builder.addMultipartAlternative(
    plainText: 'This is plain text',
    htmlText: '<p>This is <b>HTML</b></p>',
  );
  
  // Add another part
  builder.addTextPlain('Additional plain text part');
  
  final message = builder.buildMimeMessage();
  print(message.renderMessage());
}
```

## Platform Support

This library is designed to work on all Dart platforms:
- ✅ **Native platforms**: Android, iOS, Linux, macOS, Windows
- ✅ **Web platforms**: Chrome, Firefox, Safari, Edge

### Platform-Specific Notes

**File Operations:**
- The `addFile()` method uses `dart:io` and is only available on native platforms
- For web compatibility, use `addBinaryData()` or `addBinary()` methods instead
- All MIME parsing and message building features work identically across all platforms

**Example for web file uploads:**
```dart
import 'dart:typed_data';
import 'package:mime_dart/mime_dart.dart';

// In a web app, when user selects a file:
void handleFileUpload(Uint8List fileBytes, String filename) {
  final builder = MessageBuilder()
    ..from = [MailAddress('sender@example.com')]
    ..to = [MailAddress('recipient@example.com')]
    ..subject = 'File upload';
  
  // Use addBinaryData for web compatibility
  builder.addBinaryData(
    fileBytes,
    filename,
    MediaType.guessFromFileName(filename) ?? 
        MediaSubtype.applicationOctetStream.mediaType,
  );
  
  final message = builder.buildMimeMessage();
  // Send message via your email API
}
```

## Supported Encodings

### Character Encodings
- ASCII (7bit)
- UTF-8 (utf8, 8bit)
- ISO-8859-1 through ISO-8859-16 (latin-1 through latin-16)
- Windows-1250, 1251, 1252, 1253, 1254, 1256
- GB-2312, GBK, GB-18030, Chinese encodings
- Big5
- KOI8-r and KOI8-u

### Transfer Encodings
- 7bit
- 8bit
- Quoted-Printable (Q)
- Base-64 (base64)

## Related Projects

Check out these related projects:
* [enough_mail](https://github.com/Enough-Software/enough_mail) - Full IMAP, POP3, and SMTP client (the original project this was forked from)
* [enough_mail_html](https://github.com/Enough-Software/enough_mail_html) - Generates HTML from MIME messages
* [enough_mail_flutter](https://github.com/Enough-Software/enough_mail_flutter) - Flutter widgets for mail apps
* [enough_convert](https://github.com/Enough-Software/enough_convert) - Character encoding support

## Miss a feature or found a bug?

Please file feature requests and bugs at the [issue tracker](https://github.com/Enough-Software/enough_mail/issues).

## License

`mime_dart` is licensed under the commercial friendly [Mozilla Public License 2.0](LICENSE).

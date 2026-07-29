import 'package:mime_dart/src/codecs/generated_charset_registry.dart';
import 'package:test/test.dart';

void main() {
  test('vendors the complete WHATWG label set with intentional classifications',
      () {
    expect(whatwgCharsetLabels.length, 221);
    expect(whatwgReplacementCharsetLabels.length, 6);
    expect(knownUnsupportedCharsetLabels, {'x-user-defined'});
    expect(
      whatwgCharsetLabels.length +
          whatwgReplacementCharsetLabels.length +
          knownUnsupportedCharsetLabels.length,
      228,
    );
  });

  test('versioned ISO labels resolve exactly without separator guessing', () {
    expect(whatwgCharsetLabels['iso_8859-1:1987'], 'windows-1252');
    expect(whatwgCharsetLabels['iso_8859-2:1987'], 'iso-8859-2');
    expect(whatwgCharsetLabels['iso_8859-9:1989'], 'windows-1254');
  });

  test('security-sensitive and mail-meaningless labels stay out of codec map',
      () {
    for (final label in knownBlockedCharsetLabels) {
      expect(whatwgCharsetLabels, isNot(contains(label)));
      expect(pythonMimeCharsetAliases, isNot(contains(label)));
    }
    for (final label in knownUnsupportedCharsetLabels) {
      expect(whatwgCharsetLabels, isNot(contains(label)));
      expect(pythonMimeCharsetAliases, isNot(contains(label)));
    }
  });

  test('mail compatibility aliases use upgraded implementations', () {
    expect(pythonMimeCharsetAliases['cp950'], 'big5');
    expect(pythonMimeCharsetAliases['macroman'], 'macintosh');
    expect(pythonMimeCharsetAliases['koi8-t'], 'koi8-t');
    expect(pythonMimeCharsetAliases['utf-8-sig'], 'utf-8-sig');
  });

  test('ASCII-incompatible Python extras are not activated for mail', () {
    for (final label in [
      'cp037',
      'cp273',
      'cp424',
      'cp500',
      'cp864',
      'cp875',
      'cp1026',
      'cp1140',
    ]) {
      expect(pythonMimeCharsetAliases, isNot(contains(label)));
      expect(generatedSingleByteCodecNames, isNot(containsValue(label)));
    }
  });
}

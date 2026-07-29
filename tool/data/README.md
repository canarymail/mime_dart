# Charset registry source data

`encodings.json` is the machine-readable label registry from the WHATWG
Encoding Standard:

- Source: https://encoding.spec.whatwg.org/encodings.json
- SHA-256: `078212b3697f60b81225b6671bd9da2604497abff0aa8e96e4d46605c02ac9e7`
- Retrieved: 2026-07-29

Regenerate the checked-in Dart registry from the repository root with:

```sh
cd packages/mime_dart
python3 tool/generate_charset_registry.py
dart format lib/src/codecs/generated_charset_registry.dart
```

Refreshing the snapshot is an explicit reviewable operation. Do not download
registry data at application build time or runtime.

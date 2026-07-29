#!/usr/bin/env python3
"""Generate the MIME charset label registry used by MailCodec.

WHATWG is authoritative for browser-compatible label semantics. CPython's
standard codec aliases are layered on only for codecs that the pure-Dart
package intentionally supports for mail. The generated Dart is checked in so
applications never need network access at build time or runtime.
"""

from __future__ import annotations

import argparse
import encodings
import encodings.aliases
import hashlib
import importlib
import json
import pkgutil
import re
import sys
import tempfile
import urllib.request
from pathlib import Path


WHATWG_ENCODINGS_URL = "https://encoding.spec.whatwg.org/encodings.json"

# WHATWG intentionally excludes ASCII-incompatible legacy encodings. Generate
# their codec implementations in mime_convert, but do not silently activate
# them for HTML mail.
UNSAFE_PYTHON_SINGLE_BYTE = {
    "cp037",
    "cp273",
    "cp424",
    "cp500",
    "cp864",
    "cp875",
    "cp1026",
    "cp1140",
}

EXISTING_PYTHON_SINGLE_BYTE = {
    "cp850",
    "cp1250",
    "cp1251",
    "cp1252",
    "cp1253",
    "cp1254",
    "cp1256",
    "koi8_r",
    "koi8_u",
    *(f"iso8859_{number}" for number in (*range(2, 12), *range(13, 17))),
}

# Additional Python codecs whose aliases are useful in real MIME but whose
# canonical spelling differs from WHATWG's.
PYTHON_CANONICAL_OVERRIDES = {
    "ascii": "windows-1252",
    "big5": "big5",
    "cp932": "shift_jis",
    "cp936": "gbk",
    "cp949": "euc-kr",
    "cp866": "ibm866",
    "cp874": "windows-874",
    "euc_jp": "euc-jp",
    "euc_kr": "euc-kr",
    "gb18030": "gb18030",
    "gb2312": "gbk",
    "iso8859_1": "windows-1252",
    "iso8859_9": "windows-1254",
    "iso8859_11": "windows-874",
    "iso2022_jp": "iso-2022-jp",
    "latin_1": "windows-1252",
    "mac_cyrillic": "x-mac-cyrillic",
    "mac_roman": "macintosh",
    "shift_jis": "shift_jis",
    "tis_620": "windows-874",
    "utf_8": "utf-8",
    "utf_8_sig": "utf-8-sig",
    "utf_16_be": "utf-16be",
    "utf_16_le": "utf-16le",
}

KNOWN_BLOCKED_LABELS = {
    "csunicode11utf7",
    "unicode-1-1-utf-7",
    "unicode-2-0-utf-7",
    "utf-7",
    "utf7",
    "x-unicode-2-0-utf-7",
}


def _python_single_byte_names() -> set[str]:
    names: set[str] = set()
    for module_info in pkgutil.iter_modules(encodings.__path__):
        try:
            module = importlib.import_module(f"encodings.{module_info.name}")
        except Exception:
            continue
        table = getattr(module, "decoding_table", None)
        if isinstance(table, str) and len(table) == 256:
            names.add(module_info.name)
    return names


def _dart_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _dart_map(name: str, values: dict[str, str]) -> str:
    lines = [f"const Map<String, String> {name} = {{"]
    for key, value in sorted(values.items()):
        lines.append(f"  {_dart_string(key)}: {_dart_string(value)},")
    lines.append("};")
    return "\n".join(lines)


def _dart_set(name: str, values: set[str]) -> str:
    lines = [f"const Set<String> {name} = {{"]
    for value in sorted(values):
        lines.append(f"  {_dart_string(value)},")
    lines.append("};")
    return "\n".join(lines)


def _preferred_python_canonical(name: str) -> str:
    override = PYTHON_CANONICAL_OVERRIDES.get(name)
    if override is not None:
        return override
    iso_match = re.fullmatch(r"iso8859_(\d+)", name)
    if iso_match is not None:
        return f"iso-8859-{iso_match.group(1)}"
    windows_match = re.fullmatch(r"cp(125[0-8])", name)
    if windows_match is not None:
        return f"windows-{windows_match.group(1)}"
    return name.replace("_", "-")


def _load_whatwg(source: Path | None) -> tuple[bytes, list[dict]]:
    if source is not None:
        raw = source.read_bytes()
    else:
        with urllib.request.urlopen(WHATWG_ENCODINGS_URL) as response:
            raw = response.read()
    return raw, json.loads(raw)


def generate(source: Path | None, output: Path) -> None:
    raw, groups = _load_whatwg(source)
    digest = hashlib.sha256(raw).hexdigest()

    whatwg_labels: dict[str, str] = {}
    replacement_labels: set[str] = set()
    blocked = set(KNOWN_BLOCKED_LABELS)
    unsupported: set[str] = set()
    for group in groups:
        for encoding in group["encodings"]:
            canonical = encoding["name"].lower()
            labels = {label.lower() for label in encoding["labels"]}
            if canonical == "replacement":
                replacement_labels.update(labels)
                blocked.update(labels)
                continue
            if canonical == "x-user-defined":
                unsupported.update(labels)
                continue
            for label in labels:
                previous = whatwg_labels.setdefault(label, canonical)
                if previous != canonical:
                    raise ValueError(
                        f"WHATWG label collision for {label}: "
                        f"{previous} != {canonical}"
                    )

    python_names = _python_single_byte_names()
    supported_python = python_names - UNSAFE_PYTHON_SINGLE_BYTE
    canonical_by_python = {
        name: _preferred_python_canonical(name) for name in supported_python
    }
    canonical_by_python.update(PYTHON_CANONICAL_OVERRIDES)

    python_aliases: dict[str, str] = {}
    for alias, python_name in encodings.aliases.aliases.items():
        canonical = canonical_by_python.get(python_name)
        if canonical is None:
            continue
        for label in {alias.lower(), alias.lower().replace("_", "-")}:
            if label not in whatwg_labels:
                python_aliases[label] = canonical

    # Python's module names are valid and useful labels themselves.
    for python_name, canonical in canonical_by_python.items():
        if python_name in UNSAFE_PYTHON_SINGLE_BYTE:
            continue
        for label in {
            python_name.lower(),
            python_name.lower().replace("_", "-"),
        }:
            if label not in whatwg_labels:
                python_aliases[label] = canonical

    # Common Microsoft label omitted from WHATWG but frequent in mail.
    python_aliases["cp950"] = "big5"
    python_aliases["windows-31j"] = "shift_jis"

    generated_codec_names: dict[str, str] = {}
    for python_name in sorted(supported_python - EXISTING_PYTHON_SINGLE_BYTE):
        canonical = canonical_by_python[python_name]
        generated_codec_names.setdefault(canonical, python_name)
    generated_codec_names.update(
        {
            "ibm866": "cp866",
            "macintosh": "mac_roman",
            "windows-1255": "cp1255",
            "windows-1257": "cp1257",
            "windows-1258": "cp1258",
            "windows-874": "cp874",
            "x-mac-cyrillic": "mac_cyrillic",
        }
    )

    contents = f"""// GENERATED CODE - DO NOT EDIT.
// ignore_for_file: lines_longer_than_80_chars, public_member_api_docs
// ignore_for_file: prefer_single_quotes
//
// Generated by tool/generate_charset_registry.py using:
//   {WHATWG_ENCODINGS_URL}
// WHATWG source SHA-256: {digest}
// CPython: {sys.version.split()[0]}

{_dart_map("whatwgCharsetLabels", whatwg_labels)}

{_dart_map("pythonMimeCharsetAliases", python_aliases)}

{_dart_map("generatedSingleByteCodecNames", generated_codec_names)}

{_dart_set("whatwgReplacementCharsetLabels", replacement_labels)}

{_dart_set("knownBlockedCharsetLabels", blocked)}

{_dart_set("knownUnsupportedCharsetLabels", unsupported)}
"""
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(contents, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=Path("tool/data/encodings.json"),
        help="Pinned local encodings.json snapshot",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("lib/src/codecs/generated_charset_registry.dart"),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the checked-in registry differs from generated output",
    )
    args = parser.parse_args()
    if not args.check:
        generate(args.source, args.output)
        return
    with tempfile.TemporaryDirectory() as temporary_directory:
        generated = Path(temporary_directory) / args.output.name
        generate(args.source, generated)
        if not args.output.exists() or args.output.read_bytes() != generated.read_bytes():
            raise SystemExit(
                f"{args.output} is stale; run {Path(__file__).name} to regenerate"
            )


if __name__ == "__main__":
    main()

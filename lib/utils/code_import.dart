import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

final _separators = RegExp(r'[,;\s]+');
final _validCode = RegExp(r'^[A-Za-z0-9._-]{2,50}$');

/// Splits pasted or imported text into codes on commas, semicolons, spaces and
/// new lines. Quotes and a leading BOM are stripped.
List<String> splitCodes(String text) => text
    .replaceAll('﻿', '')
    .split(_separators)
    .map((c) => c.replaceAll('"', '').replaceAll("'", '').trim())
    .where((c) => c.isNotEmpty)
    .toList();

bool isValidCode(String code) => _validCode.hasMatch(code);

/// Reads a .csv, .txt or .xlsx file into plain text, one value per line.
/// A first value of "code" or "codes" is taken as a header and dropped.
String readCodesFile(String fileName, Uint8List bytes) {
  final lower = fileName.toLowerCase();
  final raw = lower.endsWith('.xlsx') ? _xlsxCells(bytes) : splitCodes(utf8.decode(bytes, allowMalformed: true));
  if (raw.isNotEmpty && (raw.first.toLowerCase() == 'code' || raw.first.toLowerCase() == 'codes')) {
    raw.removeAt(0);
  }
  return raw.join('\n');
}

/// Every cell of the first worksheet, in reading order.
List<String> _xlsxCells(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? find(String name) {
    for (final f in zip.files) {
      if (f.name == name) return f;
    }
    return null;
  }

  String text(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

  final shared = <String>[];
  final sharedFile = find('xl/sharedStrings.xml');
  if (sharedFile != null) {
    for (final si in XmlDocument.parse(text(sharedFile)).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final sheets = zip.files
      .where((f) => f.isFile && f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (sheets.isEmpty) throw const FormatException('No worksheet found in the file.');

  final out = <String>[];
  for (final c in XmlDocument.parse(text(sheets.first)).findAllElements('c')) {
    final type = c.getAttribute('t');
    String value;
    if (type == 'inlineStr') {
      value = c.findAllElements('t').map((t) => t.innerText).join();
    } else {
      final v = c.getElement('v')?.innerText ?? '';
      value = type == 's' ? (shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? '') : v;
    }
    value = value.trim();
    if (value.isNotEmpty) out.add(value);
  }
  return out;
}

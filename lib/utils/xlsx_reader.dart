import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads the first sheet of an .xlsx file as rows of text. Only values are
/// read (no formulas, styles or dates), which is all a product list needs.
List<List<String>> readXlsxRows(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? text(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content as List<int>);
  }

  final shared = <String>[];
  final ss = text('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final sheetName = zip.files
      .map((f) => f.name)
      .where((n) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(n))
      .toList()
    ..sort();
  if (sheetName.isEmpty) return [];
  final sheet = XmlDocument.parse(text(sheetName.first)!);

  int colOf(String ref) {
    var n = 0;
    for (final c in ref.codeUnits) {
      if (c < 65 || c > 90) break;
      n = n * 26 + (c - 64);
    }
    return n - 1;
  }

  final rows = <List<String>>[];
  for (final row in sheet.findAllElements('row')) {
    final cells = <int, String>{};
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? next : colOf(ref);
      next = col + 1;
      final t = c.getAttribute('t');
      var v = c.getElement('v')?.innerText ?? '';
      if (t == 's') {
        v = shared[int.tryParse(v) ?? 0];
      } else if (t == 'inlineStr') {
        v = c.findAllElements('t').map((e) => e.innerText).join();
      } else if (RegExp(r'^-?\d+\.0+$').hasMatch(v)) {
        v = v.substring(0, v.indexOf('.'));
      }
      cells[col] = v.trim();
    }
    if (cells.isEmpty) continue;
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
  }
  return rows;
}

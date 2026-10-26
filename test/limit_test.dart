// Reads the limit of workbooks as people type it. It needs no engine: Columns and Scope are plain Dart classes.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yangi_alifbo/engine.dart';
import 'package:yangi_alifbo/limit.dart';

void main() {
  test('columns are letters, and runs of them', () {
    expect(parseColumns('B, E'), [const Columns(first: 2, last: 2), const Columns(first: 5, last: 5)]);
    for (final text in ['B-C', 'b:c', 'B – C', 'C-B']) {
      expect(parseColumns(text), [const Columns(first: 2, last: 3)], reason: text);
    }
    expect(parseColumns('A;Z AA  XFD'), [
      const Columns(first: 1, last: 1),
      const Columns(first: 26, last: 26),
      const Columns(first: 27, last: 27),
      const Columns(first: 16384, last: 16384),
    ]);
    expect(parseColumns('  '), isEmpty);
  });

  test('anything else is not columns', () {
    for (final text in ['2', 'B2', 'XFE', 'ABCD', 'B-', '-B', 'B--C', 'Ö', 'B-C-D']) {
      expect(parseColumns(text), isNull, reason: text);
    }
  });

  test('columns are written back the way they are read', () {
    const runs = [
      Columns(first: 2, last: 2),
      Columns(first: 4, last: 5),
      Columns(first: 27, last: 52),
      Columns(first: 16384, last: 16384),
    ];
    expect(formatColumns(runs), 'B, D-E, AA-AZ, XFD');
    expect(parseColumns(formatColumns(runs)), runs);
  });

  test('sheets are names separated by commas', () {
    expect(parseSheets(" Ma'lumot ,Metama'lumot,, "), ["Ma'lumot", "Metama'lumot"]);
    expect(parseSheets(''), isEmpty);
  });

  test('the engine gets a scope only for a limit that is on and chooses something', () {
    const columns = [Columns(first: 2, last: 2)];
    // Records compare lists by identity, so the scope is a list of its two fields.
    List<Object?> scope(WorkbookLimit limit) => [limit.scope.sheets, limit.scope.columns];
    expect(scope(const WorkbookLimit()), [null, null]);
    expect(scope(const WorkbookLimit(sheets: ['A'], columns: columns)), [null, null]);
    expect(scope(const WorkbookLimit(on: true)), [null, null]);
    expect(scope(const WorkbookLimit(on: true, columns: columns)), [null, columns]);
    expect(scope(const WorkbookLimit(on: true, sheets: ['A'])), [
      ['A'],
      null,
    ]);
  });

  test('a saved limit is read back, and anything else is no limit', () {
    const limit = WorkbookLimit(on: true, sheets: ["Ma'lumot"], columns: [Columns(first: 2, last: 5)]);
    final read = WorkbookLimit.fromJson(jsonDecode(jsonEncode(limit.toJson())));
    expect([read.on, read.sheets, read.columns], [limit.on, limit.sheets, limit.columns]);
    for (final saved in <Object?>[
      null,
      'B',
      <String, dynamic>{},
      {'on': 'yes', 'sheets': [], 'columns': []},
      {
        'on': true,
        'sheets': [1],
        'columns': [],
      },
      {
        'on': true,
        'sheets': [],
        'columns': [
          {'first': 'B'},
        ],
      },
    ]) {
      expect(WorkbookLimit.fromJson(saved).on, isFalse, reason: '$saved');
    }
  });
}

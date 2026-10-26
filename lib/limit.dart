import 'package:yangi_alifbo/engine.dart';

/// Only some sheets and columns of each workbook, when [on]. An empty list means every sheet or every column.
class WorkbookLimit {
  const WorkbookLimit({this.on = false, this.sheets = const [], this.columns = const []});

  /// The limit as [toJson] wrote it, or none when the saved value is not one.
  factory WorkbookLimit.fromJson(Object? json) {
    if (json case {'on': final bool on, 'sheets': final List<dynamic> sheets, 'columns': final List<dynamic> columns}
        when sheets.every((name) => name is String)) {
      final runs = <Columns>[];
      for (final run in columns) {
        if (run case {'first': final int first, 'last': final int last}) {
          runs.add(Columns(first: first, last: last));
        } else {
          return const WorkbookLimit();
        }
      }
      return WorkbookLimit(on: on, sheets: sheets.cast<String>(), columns: runs);
    }
    return const WorkbookLimit();
  }

  final bool on;
  final List<String> sheets;
  final List<Columns> columns;

  Map<String, dynamic> toJson() => {
    'on': on,
    'sheets': sheets,
    'columns': [
      for (final run in columns) {'first': run.first, 'last': run.last},
    ],
  };

  WorkbookLimit copyWith({bool? on, List<String>? sheets, List<Columns>? columns}) =>
      WorkbookLimit(on: on ?? this.on, sheets: sheets ?? this.sheets, columns: columns ?? this.columns);

  /// What the engine is given: no limit when this is off or chooses neither sheets nor columns.
  Scope get scope => !on || (sheets.isEmpty && columns.isEmpty)
      ? const Scope()
      : Scope(sheets: sheets.isEmpty ? null : sheets, columns: columns.isEmpty ? null : columns);
}

// XFD, the last column of Excel.
const _lastColumn = 16384;

/// The columns in `text`: letters, or two letters joined by -, – or : for a run, separated by commas, semicolons or
/// spaces. "B, D-E" is B, D and E, and a run written backwards is turned round. An empty list for blank text, and null
/// for text that is not columns.
List<Columns>? parseColumns(String text) {
  final runs = <Columns>[];
  final tokens = text
      .replaceAll(RegExp(r'\s*[-–—:]\s*'), '-')
      .split(RegExp(r'[\s,;]+'))
      .where((token) => token.isNotEmpty);
  for (final token in tokens) {
    final match = RegExp(r'^([a-z]{1,3})(?:-([a-z]{1,3}))?$', caseSensitive: false).firstMatch(token);
    if (match == null) return null;
    final first = _columnNumber(match[1]!);
    final last = _columnNumber(match[2] ?? match[1]!);
    if (first > _lastColumn || last > _lastColumn) return null;
    runs.add(Columns(first: first < last ? first : last, last: first < last ? last : first));
  }
  return runs;
}

/// The columns as [parseColumns] reads them: "B, D-E".
String formatColumns(List<Columns> runs) => runs
    .map((run) => run.first == run.last ? _columnName(run.first) : '${_columnName(run.first)}-${_columnName(run.last)}')
    .join(', ');

/// The sheet names in `text`, separated by commas. An empty list for blank text.
List<String> parseSheets(String text) =>
    text.split(',').map((name) => name.trim()).where((name) => name.isNotEmpty).toList();

String formatSheets(List<String> names) => names.join(', ');

// A is 1, Z is 26, AA is 27.
int _columnNumber(String letters) {
  var number = 0;
  for (final unit in letters.toUpperCase().codeUnits) {
    number = number * 26 + (unit - 64);
  }
  return number;
}

String _columnName(int number) {
  var name = '';
  for (var rest = number; rest > 0; rest = (rest - 1) ~/ 26) {
    name = String.fromCharCode(65 + (rest - 1) % 26) + name;
  }
  return name;
}

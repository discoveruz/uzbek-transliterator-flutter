import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:yangi_alifbo/engine.dart';

/// Where a document is on its way to the new alphabet.
enum DocumentStatus { waiting, converting, saved, failed }

/// A Word or Excel file someone chose or dropped: the name it was saved under, or its own name when it could not be
/// converted, and what happened.
class Document {
  Document(XFile this._file, {this.bookmark}) : name = _file.name;

  /// A file that is not a Word or Excel file, which is never read.
  Document.notOffice(this.name)
    : _file = null,
      bookmark = null,
      status = DocumentStatus.failed,
      outcome = _failures[OfficeError.notOffice]!,
      finishedAt = DateTime.now();

  /// A document from the history, as [toJson] wrote it.
  Document.fromJson(Map<String, dynamic> json)
    : _file = null,
      bookmark = null,
      name = json['name'] as String,
      path = json['path'] as String?,
      status = json['saved'] == true ? DocumentStatus.saved : DocumentStatus.failed,
      outcome = json['outcome'] as String,
      finishedAt = DateTime.tryParse(json['finishedAt'] as String? ?? '');

  Map<String, dynamic> toJson() => {
    'name': name,
    if (path != null) 'path': path,
    'saved': status == DocumentStatus.saved,
    'outcome': outcome,
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
  };

  final XFile? _file;

  /// The macOS security-scoped bookmark of what was dropped: the file, or the folder it was found in.
  final Uint8List? bookmark;

  DocumentStatus status = DocumentStatus.waiting;
  String name;

  /// Where the converted file is saved, once it is.
  String? path;
  String outcome = 'Waiting';

  /// When it was saved or failed.
  DateTime? finishedAt;

  bool get finished => status == DocumentStatus.saved || status == DocumentStatus.failed;

  /// Converts the file and saves it in `folder`, next to what is there, as the kind of file the engine found in its
  /// bytes, whatever the name says. Only the scripts in `options` convert, and a workbook only within `scope`.
  Future<void> convertInto(Directory folder, {Options options = const Options(), Scope scope = const Scope()}) async {
    status = DocumentStatus.converting;
    try {
      final converted = await convertOffice(bytes: await _read(), options: options, scope: scope);
      await folder.create(recursive: true);
      final saved = _freeName(folder, name, converted.format);
      final file = await File('${folder.path}/$saved').writeAsBytes(converted.bytes, flush: true);
      name = saved;
      path = file.path;
      status = DocumentStatus.saved;
      outcome = _describe(converted.summary);
      finishedAt = DateTime.now();
    } on OfficeError catch (error) {
      _fail(_failures[error]!);
    } on FileSystemException catch (error) {
      _fail('Could not be read or saved: ${error.osError?.message ?? error.message}');
    }
  }

  void _fail(String reason) {
    status = DocumentStatus.failed;
    outcome = reason;
    finishedAt = DateTime.now();
  }

  // A sandboxed macOS app may only read a dropped file outside its container while it holds the drop's bookmark.
  Future<Uint8List> _read() async {
    final bookmark = this.bookmark;
    if (bookmark == null || bookmark.isEmpty) return _file!.readAsBytes();
    await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark);
    try {
      return await _file!.readAsBytes();
    } finally {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(bookmark: bookmark);
    }
  }
}

const _failures = {
  OfficeError.notOffice: 'Not a Word or Excel file',
  OfficeError.unsupported: 'This kind of file is not supported',
  OfficeError.encrypted: 'The file is password-protected',
  OfficeError.damaged: 'The file is damaged',
  OfficeError.refused: 'The file cannot be changed safely',
  OfficeError.cannotLimit: 'An old .xls workbook cannot be limited. Turn the limit off to convert it whole.',
};

// The kinds of file that are converted, by the extension each is chosen by: the format the engine finds in such a
// file, its MIME type, and its type identifier on Apple's systems (.xlam has one only where Excel is installed). A Word
// or Excel file with macros, or a template or an add-in, is the same format as a plain one, and keeps its extension.
const _kinds = {
  'docx': (
    OfficeFormat.docx,
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'org.openxmlformats.wordprocessingml.document',
  ),
  'docm': (
    OfficeFormat.docx,
    'application/vnd.ms-word.document.macroEnabled.12',
    'org.openxmlformats.wordprocessingml.document.macroenabled',
  ),
  'dotx': (
    OfficeFormat.docx,
    'application/vnd.openxmlformats-officedocument.wordprocessingml.template',
    'org.openxmlformats.wordprocessingml.template',
  ),
  'dotm': (
    OfficeFormat.docx,
    'application/vnd.ms-word.template.macroEnabled.12',
    'org.openxmlformats.wordprocessingml.template.macroenabled',
  ),
  'xlsx': (
    OfficeFormat.xlsx,
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'org.openxmlformats.spreadsheetml.sheet',
  ),
  'xlsm': (
    OfficeFormat.xlsx,
    'application/vnd.ms-excel.sheet.macroEnabled.12',
    'org.openxmlformats.spreadsheetml.sheet.macroenabled',
  ),
  'xltx': (
    OfficeFormat.xlsx,
    'application/vnd.openxmlformats-officedocument.spreadsheetml.template',
    'org.openxmlformats.spreadsheetml.template',
  ),
  'xltm': (
    OfficeFormat.xlsx,
    'application/vnd.ms-excel.template.macroEnabled.12',
    'org.openxmlformats.spreadsheetml.template.macroenabled',
  ),
  'xlam': (OfficeFormat.xlsx, 'application/vnd.ms-excel.addin.macroEnabled.12', 'com.microsoft.excel.openxml.addin'),
  'doc': (OfficeFormat.doc, 'application/msword', 'com.microsoft.word.doc'),
  'xls': (OfficeFormat.xls, 'application/vnd.ms-excel', 'com.microsoft.excel.xls'),
};

/// The kinds of file that are converted, by the extension each is chosen by.
final officeExtensions = _kinds.keys.toList();

/// The same kinds by MIME type, for the file chooser of Android.
final officeMimeTypes = [for (final (_, mime, _) in _kinds.values) mime];

/// The same kinds by type identifier, for the file chooser of iOS and macOS.
final officeTypeIdentifiers = [for (final (_, _, identifier) in _kinds.values) identifier];

/// The extension of `name` in lower case, without the dot: `docx` for `Hujjat.DOCX`, and an empty text for no extension.
String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Whether `name` looks like a Word or Excel file worth reading.
bool isOffice(String name) => _kinds.containsKey(_extensionOf(name));

/// The documents for what was dropped: files as they are, and the Word and Excel files anywhere inside dropped folders.
Future<List<Document>> documentsFromDrop(List<DropItem> items) async {
  final documents = <Document>[];
  for (final item in items) {
    final bookmark = item.extraAppleBookmark;
    if (item is DropItemDirectory || await FileSystemEntity.isDirectory(item.path)) {
      documents.addAll(await _officeDocumentsIn(Directory(item.path), bookmark));
    } else if (isOffice(item.name)) {
      documents.add(Document(item, bookmark: bookmark));
    } else {
      documents.add(Document.notOffice(item.name));
    }
  }
  return documents;
}

// Word's and Excel's lock files (~$name.docx) and hidden files are left out.
Future<List<Document>> _officeDocumentsIn(Directory folder, Uint8List? bookmark) async {
  final hasBookmark = bookmark != null && bookmark.isNotEmpty;
  if (hasBookmark) await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark);
  try {
    final files = await folder
        .list(recursive: true)
        .where((entity) => entity is File)
        .map((file) => XFile(file.path))
        .where((file) => isOffice(file.name) && !file.name.startsWith(r'~$') && !file.name.startsWith('.'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return [for (final file in files) Document(file, bookmark: bookmark)];
  } on FileSystemException {
    return [];
  } finally {
    if (hasBookmark) await DesktopDrop.instance.stopAccessingSecurityScopedResource(bookmark: bookmark);
  }
}

// A name in `folder` that no file has yet, for the new version of the file `name`: hujjat.docx is saved as
// hujjat-yangi.docx, then as hujjat-yangi (1).docx, the way a browser names a download. The extension is the file's
// own when it names the `format` the engine found, so hisobot.xlsm stays a .xlsm, and that format's otherwise, so a
// workbook named .xls that is a .xlsx is saved as one.
String _freeName(Directory folder, String name, OfficeFormat format) {
  final own = _extensionOf(name);
  final stem = isOffice(name) ? name.substring(0, name.length - own.length - 1) : name;
  final extension = _kinds[own]?.$1 == format ? own : format.name;
  for (var copy = 0; ; copy++) {
    final free = '$stem-yangi${copy == 0 ? '' : ' ($copy)'}.$extension';
    if (!File('${folder.path}/$free').existsSync()) return free;
  }
}

String _describe(Summary summary) {
  final parts = [
    if (summary.oldLetters > 0) _count(summary.oldLetters, 'old letter'),
    if (summary.cyrillicWords > 0) _count(summary.cyrillicWords, 'Cyrillic word'),
    if (summary.skipped > 0) '${summary.skipped} left as typed',
  ];
  return parts.isEmpty ? 'Already in the new alphabet' : parts.join(', ');
}

String _count(int count, String thing) => '$count $thing${count == 1 ? '' : 's'}';

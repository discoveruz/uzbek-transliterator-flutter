import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yangi_alifbo/yangi_alifbo.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MaterialApp(title: 'Yangi alifbo', home: ConvertPage()));
}

/// Shows what you type in the new alphabet, as you type, and saves Word documents in the new alphabet to Downloads.
class ConvertPage extends StatefulWidget {
  const ConvertPage({super.key, this.pickDocuments = _pickDocuments, this.downloads = getDownloadsDirectory});

  /// Asks which Word documents to convert.
  final Future<List<XFile>> Function() pickDocuments;

  /// The folder the converted documents are saved in.
  final Future<Directory?> Function() downloads;

  @override
  State<ConvertPage> createState() => _ConvertPageState();
}

Future<List<XFile>> _pickDocuments() => openFiles(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'Word',
      extensions: ['docx'],
      uniformTypeIdentifiers: ['org.openxmlformats.wordprocessingml.document'],
    ),
  ],
);

class _ConvertPageState extends State<ConvertPage> {
  static const _sample = 'Oʻzbekiston Respublikasi poytaxti Toshkent shahri. Ўзбекистон Республикаси';

  String _converted = '';
  int _latest = 0;
  bool _converting = false;
  List<_Document> _documents = [];

  @override
  void initState() {
    super.initState();
    _convert(_sample);
  }

  Future<void> _convert(String text) async {
    // Typing quickly starts several conversions; only the newest one is shown.
    final request = ++_latest;
    final converted = await convert(text: text);
    if (mounted && request == _latest) {
      setState(() => _converted = converted);
    }
  }

  Future<void> _convertDocuments() async {
    final files = await widget.pickDocuments();
    if (files.isEmpty) return;
    setState(() => _converting = true);
    final folder = await widget.downloads();
    final documents = [for (final file in files) await _convertDocument(file, folder)];
    if (mounted) {
      setState(() {
        _converting = false;
        _documents = documents;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yangi alifbo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(initialValue: _sample, maxLines: null, onChanged: _convert),
          const SizedBox(height: 16),
          SelectableText(_converted),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _converting ? null : _convertDocuments,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Convert Word documents'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Each one is saved to Downloads in the new alphabet.'),
          for (final document in _documents)
            ListTile(
              leading: Icon(document.saved ? Icons.download_done : Icons.error_outline),
              title: Text(document.name),
              subtitle: Text(document.outcome),
            ),
        ],
      ),
    );
  }
}

/// A document from the list: the name it was saved under, or its own name when it could not be converted, and what
/// happened.
class _Document {
  const _Document(this.name, this.outcome, {required this.saved});

  final String name;
  final String outcome;
  final bool saved;
}

Future<_Document> _convertDocument(XFile file, Directory? folder) async {
  try {
    final converted = await convertDocx(docx: await file.readAsBytes());
    if (folder == null) return _Document(file.name, 'There is no Downloads folder to save it in', saved: false);
    final name = _freeName(folder, file.name);
    await File('${folder.path}/$name').writeAsBytes(converted.docx, flush: true);
    return _Document(name, 'Saved to Downloads: ${_describe(converted.summary)}', saved: true);
  } on DocxError catch (error) {
    final outcome = error == DocxError.notWord ? 'Not a Word document' : 'The Word document is damaged';
    return _Document(file.name, outcome, saved: false);
  } on FileSystemException catch (error) {
    return _Document(file.name, 'Could not be saved: ${error.osError?.message ?? error.message}', saved: false);
  }
}

// A name in `folder` that no file has yet, for the new version of the document `name`: hujjat.docx is saved as
// hujjat-yangi.docx, then as hujjat-yangi (1).docx, the way a browser names a download.
String _freeName(Directory folder, String name) {
  final stem = name.toLowerCase().endsWith('.docx') ? name.substring(0, name.length - 5) : name;
  for (var copy = 0; ; copy++) {
    final free = '$stem-yangi${copy == 0 ? '' : ' ($copy)'}.docx';
    if (!File('${folder.path}/$free').existsSync()) return free;
  }
}

String _describe(Summary summary) => [
  _count(summary.oldLetters, 'old letter'),
  _count(summary.cyrillicWords, 'Cyrillic word'),
  if (summary.skipped > 0) '${summary.skipped} left as typed',
].join(', ');

String _count(int count, String thing) => '$count $thing${count == 1 ? '' : 's'}';

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:yangi_alifbo/document.dart';
import 'package:yangi_alifbo/settings.dart';
import 'package:yangi_alifbo/widgets/document_card.dart';
import 'package:yangi_alifbo/widgets/drop_zone.dart';

/// Converts the Word documents dropped on it or chosen, one after another, saves them in the new alphabet, and keeps
/// a history of them.
class ConvertPage extends StatefulWidget {
  const ConvertPage({
    super.key,
    required this.themeMode,
    this.pickDocuments = _pickDocuments,
    this.pickFolder = getDirectoryPath,
    this.reveal = revealInFileManager,
    this.settings = const Settings(),
  });

  /// Asks which Word documents to convert.
  final Future<List<XFile>> Function() pickDocuments;

  /// Asks which folder to save the documents in; null when none is chosen.
  final Future<String?> Function() pickFolder;

  /// Shows files or folders in the file manager, selected where that can be done.
  final Future<void> Function(List<String> paths) reveal;

  final Settings settings;

  /// Light, dark or the system's: the app follows it, and Settings changes it.
  final ValueNotifier<ThemeMode> themeMode;

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

// Android, macOS, Windows and Linux take files dropped from elsewhere; iOS does not.
final bool _canDrop = !Platform.isIOS;

class _ConvertPageState extends State<ConvertPage> {
  /// The documents still to convert, in the order they came, the one converting first.
  final List<Document> _queue = [];

  /// The documents that are done, this run's and earlier ones, the latest first.
  final List<Document> _done = [];

  /// How many documents the batch that is converting has, done or not.
  int _batch = 0;
  bool _converting = false;
  bool _dragging = false;
  bool _openFolderWhenDone = true;
  Directory? _folder;
  bool _folderIsDefault = true;

  @override
  void initState() {
    super.initState();
    widget.settings.openFolderWhenDone().then((open) {
      if (mounted) setState(() => _openFolderWhenDone = open);
    });
    widget.settings.history().then((history) {
      if (mounted) setState(() => _done.addAll(history));
    });
    _loadFolder();
  }

  Future<Directory> _loadFolder() async {
    final folder = await widget.settings.saveFolder();
    final isDefault = folder.path == (await defaultSaveFolder()).path;
    if (mounted) {
      setState(() {
        _folder = folder;
        _folderIsDefault = isDefault;
      });
    }
    return folder;
  }

  Future<void> _choose() async {
    final files = await widget.pickDocuments();
    _add([for (final file in files) isWord(file.name) ? Document(file) : Document.notWord(file.name)]);
  }

  Future<void> _drop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    _add(await documentsFromDrop(details.files));
  }

  void _add(List<Document> documents) {
    if (documents.isEmpty || !mounted) return;
    setState(() {
      for (final document in documents) {
        if (document.finished) {
          _done.insert(0, document);
        } else {
          _queue.add(document);
          _batch++;
        }
      }
    });
    _convertQueue();
  }

  // Converts one document at a time, so each card shows where it is, and documents added meanwhile join the batch.
  Future<void> _convertQueue() async {
    if (_converting || _queue.isEmpty) return;
    _converting = true;
    final folder = _folder ?? await _loadFolder();
    final saved = <String>[];
    while (_queue.isNotEmpty && mounted) {
      final document = _queue.first;
      setState(() => document.status = DocumentStatus.converting);
      await document.convertInto(folder);
      if (document.path case final path?) saved.add(path);
      if (!mounted) return;
      setState(() {
        _queue.removeAt(0);
        _done.insert(0, document);
      });
      await widget.settings.setHistory(_done);
    }
    _converting = false;
    setState(() => _batch = 0);
    if (saved.isNotEmpty && canOpenFolders && _openFolderWhenDone) await widget.reveal(saved);
  }

  // Shows the saved document selected in its folder, or the folder when the document is gone from it.
  Future<void> _reveal(Document document) async {
    final file = File(document.path!);
    if (file.existsSync()) return widget.reveal([file.path]);
    if (file.parent.existsSync()) return widget.reveal([file.parent.path]);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${document.name} was moved or deleted')));
  }

  void _clearHistory() {
    setState(_done.clear);
    widget.settings.setHistory(_done);
  }

  Future<void> _changeFolder(String? folder, StateSetter setSheetState) async {
    await widget.settings.setSaveFolder(folder);
    await _loadFolder();
    setSheetState(() {});
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text('Save to'),
                  subtitle: Text(
                    _folder == null ? '…' : describeFolder(_folder!, isDefault: _folderIsDefault),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: _folder == null ? null : () => widget.reveal([_folder!.path]),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_folderIsDefault)
                        IconButton(
                          tooltip: 'Back to app documents',
                          onPressed: () => _changeFolder(null, setSheetState),
                          icon: const Icon(Icons.restart_alt_rounded),
                        ),
                      FilledButton.tonal(
                        onPressed: () async {
                          final folder = await widget.pickFolder();
                          if (folder != null) await _changeFolder(folder, setSheetState);
                        },
                        child: const Text('Change…'),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.folder_special_outlined),
                  title: const Text('Open the folder when done'),
                  subtitle: Text('Shows the saved documents in $fileManager after each batch'),
                  value: _openFolderWhenDone,
                  onChanged: (open) {
                    setState(() => _openFolderWhenDone = open);
                    setSheetState(() {});
                    widget.settings.setOpenFolderWhenDone(open);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.contrast_rounded),
                  title: const Text('Theme'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('System')),
                        ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ],
                      selected: {widget.themeMode.value},
                      onSelectionChanged: (selected) {
                        widget.themeMode.value = selected.single;
                        setSheetState(() {});
                        widget.settings.setThemeMode(selected.single);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final empty = _queue.isEmpty && _done.isEmpty;
    final page = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (empty) SizedBox(height: MediaQuery.sizeOf(context).height * 0.08),
                    DropZone(
                      dragging: _dragging,
                      canDrop: _canDrop,
                      compact: !empty,
                      saveTo: _folder == null ? null : describeFolder(_folder!, isDefault: _folderIsDefault),
                      onChoose: _choose,
                    ),
                    if (_queue.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _Progress(done: _batch - _queue.length, total: _batch),
                      const SizedBox(height: 12),
                      for (final document in _queue) _card(document),
                    ],
                    if (_done.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Text('History', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          _Count(_done.length),
                          const Spacer(),
                          TextButton(
                            onPressed: _clearHistory,
                            style: TextButton.styleFrom(foregroundColor: colors.onSurfaceVariant),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final document in _done) _card(document),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Ö',
                style: text.titleLarge?.copyWith(color: colors.onPrimary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yangi alifbo', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  'Old Latin and Cyrillic → Ö Ğ Ş Ç',
                  style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (canOpenFolders)
            IconButton(tooltip: 'Settings', onPressed: _showSettings, icon: const Icon(Icons.tune_rounded)),
          const SizedBox(width: 12),
        ],
      ),
      body: _canDrop
          ? DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: _drop,
              child: page,
            )
          : page,
    );
  }

  Widget _card(Document document) => Padding(
    key: ObjectKey(document),
    padding: const EdgeInsets.only(bottom: 8),
    child: DocumentCard(
      document: document,
      onReveal: canOpenFolders && document.path != null ? () => _reveal(document) : null,
      revealLabel: Platform.isLinux ? 'Show in folder' : 'Show in $fileManager',
    ),
  );
}

/// How far the batch has come: "Converting 2 of 5" over a bar.
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Converting ${done + 1} of $total', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${(done * 100 / total).round()}%', style: text.labelLarge?.copyWith(color: colors.primary)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: done / total),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 6),
          ),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yangi_alifbo/engine.dart';
import 'package:yangi_alifbo/convert_page.dart';
import 'package:yangi_alifbo/document.dart';
import 'package:yangi_alifbo/settings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  test('converts through the plugin as an app bundles it', () async {
    expect(await convert(text: 'Toshkent shahri, Ўзбекистон'), 'Toşkent şahri, Özbekiston');
  });

  testWidgets('saves the chosen Word documents in the new alphabet, shows them, and keeps them in the history', (
    tester,
  ) async {
    // The documents come straight from the test instead of from the file dialog, and go to a folder of the test's own.
    final hello = (await rootBundle.load('integration_test/hello.docx')).buffer.asUint8List();
    final folder = await Directory.systemTemp.createTemp('saved');
    addTearDown(() => folder.delete(recursive: true));
    final settings = _MemorySettings(folder);
    final themeMode = ValueNotifier(ThemeMode.system);
    final revealed = <List<String>>[];
    final shared = <List<String>>[];
    Widget app() => MaterialApp(
      home: ConvertPage(
        key: UniqueKey(),
        themeMode: themeMode,
        pickDocuments: () async => [
          // Outside the web, an XFile made from bytes takes its name from the path.
          XFile.fromData(hello, path: 'hello.docx'),
          XFile.fromData(utf8.encode('Toshkent'), path: 'notes.docx'),
        ],
        reveal: (paths) async => revealed.add(paths),
        share: (paths, origin) async => shared.add(paths),
        settings: settings,
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // Desktops take documents dropped on the window; phones only choose them.
    expect(find.text(canOpenFolders ? 'Drop Word documents here' : 'Choose Word documents'), findsOneWidget);

    await tester.tap(find.text('Choose files'));
    await pumpUntilFound(tester, find.text('hello-yangi.docx'));
    // The documents convert one at a time, and notes.docx, which is not a Word document, comes last.
    await pumpUntilFound(tester, find.textContaining('Not a Word document'));
    expect(find.text('hello-yangi.docx'), findsOneWidget);
    expect(find.textContaining('3 old letters, 2 Cyrillic words, 1 left as typed'), findsOneWidget);
    expect(find.text('notes.docx'), findsOneWidget);
    expect(find.textContaining('Not a Word document'), findsOneWidget);
    final saved = await File('${folder.path}/hello-yangi.docx').readAsBytes();
    expect((await convertDocx(docx: saved)).summary.oldLetters, 0);
    await tester.pumpAndSettle();
    // When the batch is done, the file manager shows what it saved. A phone has none, and shows nothing.
    expect(revealed, [
      if (canOpenFolders) ['${folder.path}/hello-yangi.docx'],
    ]);

    await tester.tap(find.text('Choose files'));
    await pumpUntilFound(tester, find.text('hello-yangi (1).docx'));
    await pumpUntilFound(tester, find.textContaining('Not a Word document'), count: 2);
    expect(File('${folder.path}/hello-yangi.docx').readAsBytesSync(), saved);
    await tester.pumpAndSettle();
    expect(revealed, hasLength(canOpenFolders ? 2 : 0));

    // After a restart the history is still there, and a document's own button shows it, or on a phone shares it.
    settings.open = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('hello-yangi.docx'), findsOneWidget);
    expect(find.text('hello-yangi (1).docx'), findsOneWidget);
    expect(find.text('notes.docx'), findsNWidgets(2));
    final button = find.byTooltip(canOpenFolders ? 'Show in Finder' : 'Share').last;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    expect((canOpenFolders ? revealed : shared).last, ['${folder.path}/hello-yangi.docx']);

    // With the setting off, nothing is shown when a batch is done.
    await tester.ensureVisible(find.text('Choose files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose files'));
    await pumpUntilFound(tester, find.text('hello-yangi (2).docx'));
    await pumpUntilFound(tester, find.textContaining('Not a Word document'), count: 3);
    await tester.pumpAndSettle();
    expect(revealed, hasLength(canOpenFolders ? 3 : 0));
    expect(shared, hasLength(canOpenFolders ? 0 : 1));

    // The theme chosen in Settings is applied and kept. Phones share the documents, so they have no folder settings.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Open the folder when done'), canOpenFolders ? findsOneWidget : findsNothing);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(themeMode.value, ThemeMode.dark);
    expect(settings.theme, ThemeMode.dark);
  });
}

// Pumps frames until `finder` finds `count` widgets: the conversion finishes outside the frames the test pumps.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {int count = 1}) async {
  for (var tries = 0; tries < 100 && finder.evaluate().length < count; tries++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _MemorySettings implements Settings {
  _MemorySettings(this.folder);

  Directory folder;
  bool open = true;
  ThemeMode theme = ThemeMode.system;
  List<Map<String, dynamic>> saved = [];

  @override
  Future<bool> openFolderWhenDone() async => open;

  @override
  Future<void> setOpenFolderWhenDone(bool open) async => this.open = open;

  @override
  Future<ThemeMode> themeMode() async => theme;

  @override
  Future<void> setThemeMode(ThemeMode mode) async => theme = mode;

  @override
  Future<Directory> saveFolder() async => folder;

  @override
  Future<void> setSaveFolder(String? folder) async => this.folder = Directory(folder ?? this.folder.path);

  @override
  Future<List<Document>> history() async => [for (final entry in saved) Document.fromJson(entry)];

  @override
  Future<void> setHistory(List<Document> documents) async =>
      saved = [for (final document in documents) document.toJson()];
}

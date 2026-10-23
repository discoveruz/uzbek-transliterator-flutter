import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yangi_alifbo/engine.dart';
import 'package:yangi_alifbo/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  test('converts through the plugin as an app bundles it', () async {
    expect(await convert(text: 'Toshkent shahri, Ўзбекистон'), 'Toşkent şahri, Özbekiston');
  });

  testWidgets('saves the chosen Word documents in the new alphabet, next to what is there', (tester) async {
    // The documents come straight from the test instead of from the file dialog, and go to a folder of the test's own.
    final hello = (await rootBundle.load('integration_test/hello.docx')).buffer.asUint8List();
    final downloads = await Directory.systemTemp.createTemp('downloads');
    addTearDown(() => downloads.delete(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: ConvertPage(
          pickDocuments: () async => [
            // Outside the web, an XFile made from bytes takes its name from the path.
            XFile.fromData(hello, path: 'hello.docx'),
            XFile.fromData(utf8.encode('Toshkent'), path: 'notes.docx'),
          ],
          downloads: () async => downloads,
        ),
      ),
    );

    await tester.tap(find.text('Convert Word documents'));
    await pumpUntilFound(tester, find.text('hello-yangi.docx'));
    expect(find.text('hello-yangi.docx'), findsOneWidget);
    expect(find.text('Saved to Downloads: 3 old letters, 2 Cyrillic words, 1 left as typed'), findsOneWidget);
    expect(find.text('notes.docx'), findsOneWidget);
    expect(find.text('Not a Word document'), findsOneWidget);
    final saved = await File('${downloads.path}/hello-yangi.docx').readAsBytes();
    expect((await convertDocx(docx: saved)).summary.oldLetters, 0);

    await tester.tap(find.text('Convert Word documents'));
    await pumpUntilFound(tester, find.text('hello-yangi (1).docx'));
    expect(find.text('hello-yangi (1).docx'), findsOneWidget);
    expect(File('${downloads.path}/hello-yangi.docx').readAsBytesSync(), saved);
  });
}

// Pumps frames until `finder` finds something: the conversion finishes outside the frames the test pumps.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var tries = 0; tries < 100 && finder.evaluate().isEmpty; tries++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

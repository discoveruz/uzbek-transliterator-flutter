// Calls the engine through the bridge, the way a Flutter app does. Build the Rust library first, then run the tests:
// (cd rust && cargo build --release) && flutter test
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yangi_alifbo/engine.dart';

// hello.docx has three paragraphs: "Oʻzbekiston Respublikasi poytaxti Toshkent shahri", with Tosh in bold in a run of
// its own, then "Ўзбекистон Республикаси" and "Batafsil: https://shop.uz".
final hello = File('test/hello.docx').readAsBytesSync();

void main() {
  setUpAll(() async => RustLib.init());

  test('converts old Latin and Cyrillic', () async {
    expect(
      await convert(text: 'Oʻzbekiston Respublikasi poytaxti Toshkent shahri'),
      'Özbekiston Respublikasi poytaxti Toşkent şahri',
    );
    expect(await convert(text: 'Ўзбекистон Республикаси'), 'Özbekiston Respublikasi');
  });

  test('options choose the scripts, and one left out means yes', () async {
    const text = 'Oʻzbekiston Ўзбекистон';
    expect(await convert(text: text, options: const Options(cyrillic: false)), 'Özbekiston Ўзбекистон');
    expect(await convert(text: text, options: const Options(oldLatin: false)), 'Oʻzbekiston Özbekiston');
    expect(await convert(text: text, options: const Options()), 'Özbekiston Özbekiston');
  });

  test('change offsets index the Dart string', () async {
    const text = '😀 Oʻzbekiston shop.uz Тошкент';
    final changes = await analyze(text: text);
    expect(changes.map((c) => (c.kind, c.start, c.end, c.original, c.replacement, c.skip)).toList(), [
      (ChangeKind.oldLatin, 3, 14, 'Oʻzbekiston', 'Özbekiston', null),
      (ChangeKind.oldLatin, 15, 19, 'shop', 'şop', SkipReason.link),
      (ChangeKind.cyrillic, 23, 30, 'Тошкент', 'Toşkent', null),
    ]);
    for (final change in changes) {
      expect(text.substring(change.start, change.end), change.original);
    }
  });

  test('apply writes the changes it is given, skipped or not', () async {
    const text = '😀 Toshkent Chicago';
    final changes = await analyze(text: text);
    expect(changes[1].skip, SkipReason.notUzbek);
    expect(await apply(text: text, changes: [changes[0]]), '😀 Toşkent Chicago');
    expect(await apply(text: text, changes: [changes[1]]), '😀 Toshkent Çicago');
    expect(await apply(text: text, changes: const []), text);
  });

  test('apply leaves out a change that no longer fits the text', () async {
    final changes = await analyze(text: 'Toshkent shahri');
    expect(await apply(text: 'Tosskent shahri', changes: [changes[0]]), 'Tosskent shahri');
    const outside = Change(
      kind: ChangeKind.oldLatin,
      start: 40,
      end: 48,
      original: 'Toshkent',
      replacement: 'Toşkent',
    );
    expect(await apply(text: 'Toshkent shahri', changes: const [outside]), 'Toshkent shahri');
  });

  test('summarize counts what convert writes and what it skips', () async {
    final summary = await summarize(changes: await analyze(text: 'Oʻzbekiston qoʻshiq Тошкент shop.uz Chicago'));
    expect((summary.oldLetters, summary.cyrillicWords, summary.skipped), (3, 1, 2));
  });

  test('convertDocx gives a converted Word document and what it converted', () async {
    final converted = await convertDocx(docx: hello);
    expect(converted.docx.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
    final summary = converted.summary;
    expect((summary.oldLetters, summary.cyrillicWords, summary.skipped), (3, 2, 1));
    // Only the link is left, as typed.
    final again = (await convertDocx(docx: converted.docx)).summary;
    expect((again.oldLetters, again.cyrillicWords, again.skipped), (0, 0, 1));
  });

  test('convertDocx converts only the chosen scripts', () async {
    final summary = (await convertDocx(docx: hello, options: const Options(cyrillic: false))).summary;
    expect((summary.oldLetters, summary.cyrillicWords, summary.skipped), (3, 0, 1));
  });

  test('convertDocx throws for what is not a Word document', () async {
    await expectLater(convertDocx(docx: utf8.encode('Toshkent')), throwsA(DocxError.notWord));
    await expectLater(convertDocx(docx: hello.sublist(0, 600)), throwsA(isA<DocxError>()));
  });
}

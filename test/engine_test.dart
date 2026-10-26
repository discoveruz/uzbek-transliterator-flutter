// Calls the engine through the bridge, the way a Flutter app does. Build the Rust library first, then run the tests:
// (cd rust && cargo build --release) && flutter test
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yangi_alifbo/engine.dart';

// hello.docx has three paragraphs: "Oʻzbekiston Respublikasi poytaxti Toshkent shahri", with Tosh in bold in a run of
// its own, then "Ўзбекистон Республикаси" and "Batafsil: https://shop.uz".
final hello = File('test/hello.docx').readAsBytesSync();

// The workbook (.xlsx and .xls) is a stat.uz export with the same rows in Uzbek Latin, Russian, English and Cyrillic;
// the .doc is a regulation of a university department. The engine's own tests describe them.
final xlsx = File('test/sample.xlsx').readAsBytesSync();
final xls = File('test/sample.xls').readAsBytesSync();
final doc = File('test/sample.doc').readAsBytesSync();

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
    const outside = Change(kind: ChangeKind.oldLatin, start: 40, end: 48, original: 'Toshkent', replacement: 'Toşkent');
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

  test('convertOffice reads the kind of file from its bytes and gives the same kind back', () async {
    const zip = [0x50, 0x4b, 0x03, 0x04];
    const compound = [0xd0, 0xcf, 0x11, 0xe0];
    for (final (format, input, start) in [
      (OfficeFormat.docx, hello, zip),
      (OfficeFormat.xlsx, xlsx, zip),
      (OfficeFormat.xls, xls, compound),
      (OfficeFormat.doc, doc, compound),
    ]) {
      final converted = await convertOffice(bytes: input);
      expect(converted.format, format);
      expect(converted.bytes.sublist(0, 4), start, reason: '$format');
      expect(converted.summary.oldLetters + converted.summary.cyrillicWords, greaterThan(0), reason: '$format');
      // Converting again changes nothing more.
      final again = await convertOffice(bytes: converted.bytes);
      expect(again.format, format);
      expect((again.summary.oldLetters, again.summary.cyrillicWords), (0, 0), reason: '$format');
    }
  });

  test('convertOffice converts only the chosen scripts', () async {
    final summary = (await convertOffice(bytes: hello, options: const Options(cyrillic: false))).summary;
    expect((summary.oldLetters, summary.cyrillicWords, summary.skipped), (3, 0, 1));
  });

  // The Uzbek columns of the first sheet of the workbook: Latin in B, Cyrillic in E. Russian and English are in C and D.
  const uzbekColumns = Scope(sheets: ["Ma'lumot"], columns: [Columns(first: 2, last: 2), Columns(first: 5, last: 5)]);
  int total(ConvertedOffice converted) => converted.summary.oldLetters + converted.summary.cyrillicWords;

  test('convertOffice limits a workbook to some sheets and columns', () async {
    final whole = await convertOffice(bytes: xlsx);
    final limited = await convertOffice(bytes: xlsx, scope: uzbekColumns);
    expect(limited.format, OfficeFormat.xlsx);
    expect(total(limited), allOf(greaterThan(0), lessThan(total(whole))));
    // The rest is as it was, so converting it whole afterwards still finds old text.
    expect(total(await convertOffice(bytes: limited.bytes)), greaterThan(0));
    // Every column of one sheet, and one column of every sheet.
    expect(
      total(
        await convertOffice(
          bytes: xlsx,
          scope: const Scope(sheets: ["ma'lumot"]),
        ),
      ),
      lessThan(total(whole)),
    );
    expect(
      total(
        await convertOffice(
          bytes: xlsx,
          scope: const Scope(columns: [Columns(first: 2, last: 2)]),
        ),
      ),
      lessThan(total(whole)),
    );
  });

  test('a limit leaves Word documents whole, and turns old workbooks down', () async {
    expect(total(await convertOffice(bytes: hello, scope: uzbekColumns)), total(await convertOffice(bytes: hello)));
    expect(total(await convertOffice(bytes: doc, scope: uzbekColumns)), total(await convertOffice(bytes: doc)));
    await expectLater(convertOffice(bytes: xls, scope: uzbekColumns), throwsA(OfficeError.cannotLimit));
    await expectLater(
      convertOffice(
        bytes: xls,
        scope: const Scope(sheets: ["Ma'lumot"]),
      ),
      throwsA(OfficeError.cannotLimit),
    );
    expect((await convertOffice(bytes: xls, scope: const Scope())).format, OfficeFormat.xls);
  });

  test('convertOffice throws the reason a file is not converted', () async {
    await expectLater(convertOffice(bytes: utf8.encode('Toshkent')), throwsA(OfficeError.notOffice));
    await expectLater(convertOffice(bytes: Uint8List(0)), throwsA(OfficeError.notOffice));
    // The FIB of a .doc starts with 0xA5EC; a Word 6 file has 0xA5DC, and the password flag is a bit of byte 11.
    final fib = [
      for (var i = 0; i < doc.length - 2; i++)
        if (doc[i] == 0xec && doc[i + 1] == 0xa5 && doc[i + 2] == 0xc1) i,
    ].first;
    final word6 = Uint8List.fromList(doc)..[fib] = 0xdc;
    final locked = Uint8List.fromList(doc)..[fib + 11] |= 1;
    await expectLater(convertOffice(bytes: word6), throwsA(OfficeError.unsupported));
    await expectLater(convertOffice(bytes: locked), throwsA(OfficeError.encrypted));
    await expectLater(convertOffice(bytes: doc.sublist(0, 700)), throwsA(OfficeError.damaged));
  });
}

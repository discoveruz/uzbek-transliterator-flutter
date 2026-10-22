# yangi_alifbo

The [yangi-alifbo engine](https://github.com/discoveruz/uzbek-transliterator-engine) for Flutter. It writes Uzbek text
and Word documents in the new Latin alphabet (Ö, Ğ, Ş, Ç), from old Latin and from Cyrillic. The rules live in the Rust engine; this
package calls it through [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/) on Android, iOS, macOS,
Windows and Linux. The engine's README lists what converts and what stays as typed.

## Using it

Add the package as a path or git dependency, for example:

```yaml
dependencies:
  yangi_alifbo:
    git:
      url: https://github.com/discoveruz/uzbek-transliterator-flutter
```

Building an app compiles the Rust code and downloads the engine from GitHub, so the build machine needs Rust (rustup).

```dart
import 'package:yangi_alifbo/yangi_alifbo.dart';

Future<void> main() async {
  await RustLib.init();
  print(await convert(text: 'Oʻzbekiston Respublikasi')); // Özbekiston Respublikasi
}
```

| Function | What it gives |
|---|---|
| `convert(text:, options:)` | The text in the new alphabet. Links and words that aren't Uzbek stay as typed |
| `analyze(text:, options:)` | Every word that changes, as a `Change`, including those left as typed (`skip` is set) |
| `apply(text:, changes:)` | The text with exactly the given changes, for a preview where people untick some |
| `summarize(changes:)` | How many old letters and Cyrillic words the changes convert, and how many they skip |
| `convertDocx(docx:, options:)` | A Word document (.docx) with its text converted: its bytes (`docx`) and a `summary` |

`start` and `end` of a `Change` index the Dart string: `text.substring(change.start, change.end)` is
`change.original`. `Options(oldLatin: false)` or `Options(cyrillic: false)` converts only one script.

A Word document keeps everything but its text as it was:

```dart
final converted = await convertDocx(docx: await File('hujjat.docx').readAsBytes());
await File('hujjat-yangi.docx').writeAsBytes(converted.docx);
```

It throws `DocxError.notWord` for a file that is not a Word document, and `DocxError.damaged` for a broken one.

A sandboxed macOS app needs two entitlements in `macos/Runner/*.entitlements` to open the documents people choose and
save to Downloads: `com.apple.security.files.user-selected.read-only` and
`com.apple.security.files.downloads.read-write`. The example app has both.

## Working on it

After changing `rust/src/api/`, regenerate the Dart side with `flutter_rust_bridge_codegen generate`. The tests call
the engine through the bridge, on text and on the Word document `test/hello.docx`:

```
(cd rust && cargo build --release) && flutter test
```

`example/` is a small app that converts as you type. Its **Convert Word documents** button asks for .docx files and
saves each one to Downloads as `name-yangi.docx`. `example/integration_test` runs the plugin inside the app, and
presses that button with `hello.docx` in place of the file dialog:
`(cd example && flutter test integration_test -d macos)`.

`rust/Cargo.toml` takes the engine from GitHub at a tag. To try changes in a local copy of the engine first, keep the
two folders side by side and create `.cargo/config.toml` in this folder:

```toml
[patch."https://github.com/discoveruz/uzbek-transliterator-engine"]
yangi-alifbo = { path = "../uzbek-transliterator-engine" }
```

The Rust build for `flutter test` and the example app's build both use it. Git ignores that file, so it stays on your
machine. Delete it to go back to the tagged engine.

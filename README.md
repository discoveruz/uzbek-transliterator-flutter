# Yangi alifbo — Flutter app

A Flutter app for Android, iOS, macOS, Windows and Linux that writes Uzbek text and Word documents in the new Latin
alphabet (Ö, Ğ, Ş, Ç), from old Latin and from Cyrillic. The rules live in the Rust
[yangi-alifbo engine](https://github.com/discoveruz/uzbek-transliterator-engine), which the app calls through
[flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/). The engine's README lists what converts and what
stays as typed.

## Run it

Needs Flutter and Rust (rustup). The first build compiles the Rust code and downloads the engine from GitHub.

```
flutter run -d macos        # or an Android or iOS device, windows, linux
```

| Platform | Build |
|----------|-------|
| Android | `flutter build apk` or `flutter build appbundle` |
| iOS | `flutter build ipa` |
| macOS | `flutter build macos` |
| Windows | `flutter build windows` |
| Linux | `flutter build linux` |

The app id is `uz.yangialifbo.app` on every platform.

## Project layout

| Path | What it holds |
|------|---------------|
| `lib/main.dart` | Starts the app, with its light and dark themes |
| `lib/convert_page.dart` | The screen: drop or choose Word documents, watch each one convert, open the folder |
| `lib/document.dart` | A document on its way through the queue, and how it is converted and named |
| `lib/settings.dart` | What the app keeps between runs (save folder, "Open the folder when done", history), and showing files in Finder or Explorer |
| `lib/widgets/` | The drop zone and the document cards |
| `lib/engine.dart` | The engine's functions, for the app's code to import |
| `lib/src/rust/` | Bindings that flutter_rust_bridge generates; not edited by hand |
| `rust/` | The Rust crate that exposes the engine to Dart (`rust/src/api/transliterator.rs`) |
| `rust_builder/` | Builds `rust/` with cargokit and bundles it with the app on each platform |
| `test/` | Calls the engine through the bridge |
| `integration_test/` | Runs the app and converts a Word document in it |

`lib/engine.dart` gives `convert`, `analyze`, `apply`, `summarize` and `convertDocx`. Call `await RustLib.init()` once
before them, as `main()` does. A `Change`'s `start` and `end` index the Dart string. `Options(oldLatin: false)` or
`Options(cyrillic: false)` converts only one script. `convertDocx` throws `DocxError.notWord` for a file that is not a
Word document, and `DocxError.damaged` for a broken one.

Converted documents go to the app's own Documents folder (on macOS, `~/Library/Containers/uz.yangialifbo.app/Data/Documents`;
on Windows and Linux, `Documents/Yangi alifbo`) until another folder is chosen in Settings.

The macOS app is sandboxed. `com.apple.security.files.user-selected.read-write` lets it read the documents people
choose or drop and write to the folder they choose; `com.apple.security.files.bookmarks.app-scope` lets it keep that
folder after a restart, through a bookmark (`macos/Runner/MainFlutterWindow.swift`). Finder is asked to reveal files
rather than open folders, which the sandbox does not allow.

## Changing the Rust side

After changing `rust/src/api/`, regenerate the Dart side:

```
flutter_rust_bridge_codegen generate
```

## Tests

```
(cd rust && cargo build --release) && flutter test     # the engine through the bridge
flutter test integration_test -d macos                 # inside the app
```

The integration test presses **Convert Word documents** with `integration_test/hello.docx` in place of the file dialog.

## Working on the engine at the same time

`rust/Cargo.toml` takes the engine from GitHub at a tag. To try changes in a local copy of the engine first, keep the
two repositories side by side and create `.cargo/config.toml` in this folder:

```toml
[patch."https://github.com/discoveruz/uzbek-transliterator-engine"]
yangi-alifbo = { path = "../uzbek-transliterator-engine" }
```

`flutter test` and the app's builds both use it. Git ignores that file. Delete it to go back to the tagged engine.

# Yangi alifbo — Flutter app

A Flutter app for Android, iOS, macOS, Windows and Linux that writes Uzbek Word and Excel files (.docx, .xlsx, .doc,
.xls) in the new Latin alphabet (Ö, Ğ, Ş, Ç), from old Latin and from Cyrillic. The rules live in the Rust
[yangi-alifbo engine](https://github.com/discoveruz/uzbek-transliterator-engine), which the app calls through
[flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/). The engine's README lists what converts and what
stays as typed.

Choose Word and Excel files, as many as you like, or on a desktop drop them, or folders of them, on the window. Each one
is converted in turn and saved as a new file of the same kind: `hujjat.docx` becomes `hujjat-yangi.docx`, then
`hujjat-yangi (1).docx`, the way a browser names a download. The kind is read from the file's bytes, so a workbook named
`.xls` that is really an `.xlsx` is saved as one. In Excel files all the text is converted, Russian and English columns
too. The history keeps the saved files between runs. On a desktop a saved
file's button shows it in Finder, Explorer or the file manager; on a phone it shares the document.

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
| `lib/convert_page.dart` | The screen: choose or drop Word and Excel files, watch each one convert, show or share what was saved |
| `lib/document.dart` | A document on its way through the queue, and how it is converted and named |
| `lib/settings.dart` | What the app keeps between runs (save folder, "Open the folder when done", history), and showing files in Finder or Explorer, or sharing them on phones |
| `lib/widgets/` | The drop zone and the document cards |
| `lib/engine.dart` | The engine's functions, for the app's code to import |
| `lib/src/rust/` | Bindings that flutter_rust_bridge generates; not edited by hand |
| `rust/` | The Rust crate that exposes the engine to Dart (`rust/src/api/transliterator.rs`) |
| `rust_builder/` | Builds `rust/` with cargokit and bundles it with the app on each platform |
| `test/` | Calls the engine through the bridge |
| `integration_test/` | Runs the app and converts Word and Excel files in it |

`lib/engine.dart` gives `convert`, `analyze`, `apply`, `summarize`, `convertDocx` and `convertOffice`. Call `await RustLib.init()` once
before them, as `main()` does. A `Change`'s `start` and `end` index the Dart string. `Options(oldLatin: false)` or
`Options(cyrillic: false)` converts only one script. `convertDocx` throws `DocxError.notWord` for a file that is not a
Word document, and `DocxError.damaged` for a broken one. `convertOffice` takes a Word or Excel file of any kind and gives
the same kind back (`ConvertedOffice.format`); it throws an `OfficeError`: `notOffice`, `unsupported` (an .xlsb or a
Word 6 file), `encrypted`, `damaged` or `refused` (something in the file that cannot be rewritten safely).

On a desktop, converted documents go to the app's own Documents folder (on macOS,
`~/Library/Containers/uz.yangialifbo.app/Data/Documents`; on Windows and Linux, `Documents/Yangi alifbo`) until another
folder is chosen in Settings.

The macOS app is sandboxed. `com.apple.security.files.user-selected.read-write` lets it read the documents people
choose or drop and write to the folder they choose; `com.apple.security.files.bookmarks.app-scope` lets it keep that
folder after a restart, through a bookmark (`macos/Runner/MainFlutterWindow.swift`). Finder is asked to reveal files
rather than open folders, which the sandbox does not allow.

## On Android and iOS

Phones choose documents with the system file picker. They do not take dropped files: iOS has no drop, and Android hands
over `content://` links that `dart:io` cannot read. The converted documents are saved in the app's own Documents
folder, and each one has a **Share** button that offers it to other apps through the share sheet: Files, Word, a chat
or mail. On iOS that folder is also in the Files app, under On My iPhone › Yangi alifbo (`UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` in `ios/Runner/Info.plist`). Settings has only the theme on phones.

## Changing the Rust side

After changing `rust/src/api/`, regenerate the Dart side:

```
flutter_rust_bridge_codegen generate
```

## Tests

```
(cd rust && cargo build --release) && flutter test     # the engine through the bridge
flutter test integration_test -d macos                 # inside the app
flutter test integration_test -d <device>              # inside the app on an Android emulator or the iOS simulator
```

The integration test presses **Choose files** with `integration_test/hello.docx` and a file that is not a Word or Excel
file in place of the file dialog, and then once more with a workbook. It checks the saved documents and their names, the history after a restart, each
document's button (**Show in Finder** on macOS, **Share** on a phone), and the theme in Settings.

## Working on the engine at the same time

`rust/Cargo.toml` takes the engine from GitHub at a tag. To try changes in a local copy of the engine first, keep the
two repositories side by side and create `.cargo/config.toml` in this folder:

```toml
[patch."https://github.com/discoveruz/uzbek-transliterator-engine"]
yangi-alifbo = { path = "../uzbek-transliterator-engine" }
```

`flutter test` and the app's builds both use it. Git ignores that file. Delete it to go back to the tagged engine.

## CI and releases

`.github/workflows/ci.yml` runs `flutter analyze`, builds the Rust library and runs `flutter test` on every push to
`main` and every pull request.

`.github/workflows/release.yml` builds the app for Android, Linux, macOS and Windows. Pushing a tag publishes the builds
as a release on this repository's [Releases](https://github.com/discoveruz/uzbek-transliterator-flutter/releases) page:

```
git tag v1.0.0 && git push origin v1.0.0
```

The tag is the version (`1.0.0`), and the workflow's run number is the build number. Each file keeps its name in every
release, so `https://github.com/discoveruz/uzbek-transliterator-flutter/releases/latest/download/yangi-alifbo-android.apk`
(or `-macos.zip`, `-windows-x64.zip`, `-linux-x64.tar.gz`) is always the newest. Running the workflow by hand from the
Actions tab only builds; its builds are kept with the run.

The workflows need these repository secrets:

| Secret | What it is |
|--------|------------|
| `ENGINE_DEPLOY_KEY` | The private half of a read-only deploy key on the engine repository, so Cargo can fetch the engine |
| `ANDROID_KEYSTORE_BASE64` | The Android release keystore, in base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Its password (the key's alias is `upload`) |

Android release builds are signed with the key that `android/key.properties` names (`storeFile`, `storePassword`,
`keyAlias`, `keyPassword`), or with the debug key when there is no such file. Git ignores it. Every update of the app
must be signed with the same release key, so keep a copy of the keystore somewhere safe.

## License

MIT; see [LICENSE](LICENSE).

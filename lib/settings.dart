import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Rect, ThemeMode;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yangi_alifbo/document.dart';

/// Whether this platform has a file manager to show folders in: Finder, Explorer or the Linux one. Phones have none,
/// and share the documents instead.
final bool canOpenFolders = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// What this platform's file manager is called.
final String fileManager = Platform.isMacOS
    ? 'Finder'
    : Platform.isWindows
    ? 'Explorer'
    : 'the file manager';

const _finder = MethodChannel('yangi_alifbo/finder');

/// What the app keeps between runs: the choices made in Settings and the documents converted.
class Settings {
  const Settings();

  static const _openFolderWhenDone = 'openFolderWhenDone';
  static const _saveFolder = 'saveFolder';
  static const _saveFolderBookmark = 'saveFolderBookmark';
  static const _history = 'history';
  static const _themeMode = 'themeMode';

  /// How many converted documents the history keeps.
  static const historyLength = 200;

  /// Whether the documents are shown in the file manager when a batch of them is done. On unless turned off.
  Future<bool> openFolderWhenDone() async => await SharedPreferencesAsync().getBool(_openFolderWhenDone) ?? true;

  Future<void> setOpenFolderWhenDone(bool open) => SharedPreferencesAsync().setBool(_openFolderWhenDone, open);

  /// Whether the app is light, dark or follows the system. Follows the system unless chosen otherwise.
  Future<ThemeMode> themeMode() async {
    final saved = await SharedPreferencesAsync().getString(_themeMode);
    return ThemeMode.values.firstWhere((mode) => mode.name == saved, orElse: () => ThemeMode.system);
  }

  Future<void> setThemeMode(ThemeMode mode) => SharedPreferencesAsync().setString(_themeMode, mode.name);

  /// The folder the converted documents are saved in: the one chosen in Settings, or [defaultSaveFolder] when none
  /// is, or when the chosen one can no longer be reached.
  Future<Directory> saveFolder() async {
    final store = SharedPreferencesAsync();
    final chosen = await store.getString(_saveFolder);
    if (chosen == null) return defaultSaveFolder();
    if (!Platform.isMacOS) return Directory(chosen);
    // A sandboxed macOS app gets back into a folder chosen in an earlier run only through its bookmark.
    final bookmark = await store.getString(_saveFolderBookmark);
    final path = bookmark == null ? null : await _finder.invokeMethod<String>('access', base64Decode(bookmark));
    return path == null ? defaultSaveFolder() : Directory(path);
  }

  /// Saves the documents in `folder` from now on, or in [defaultSaveFolder] when `folder` is null.
  Future<void> setSaveFolder(String? folder) async {
    final store = SharedPreferencesAsync();
    if (folder == null) {
      await store.remove(_saveFolder);
      await store.remove(_saveFolderBookmark);
      return;
    }
    if (Platform.isMacOS) {
      final bookmark = await _finder.invokeMethod<Uint8List>('bookmark', folder);
      if (bookmark == null) return;
      await store.setString(_saveFolderBookmark, base64Encode(bookmark));
    }
    await store.setString(_saveFolder, folder);
  }

  /// The documents converted before, the latest first.
  Future<List<Document>> history() async {
    final saved = await SharedPreferencesAsync().getString(_history);
    if (saved == null) return [];
    try {
      return [for (final entry in jsonDecode(saved) as List) Document.fromJson(entry as Map<String, dynamic>)];
    } on FormatException {
      return [];
    }
  }

  Future<void> setHistory(List<Document> documents) => SharedPreferencesAsync().setString(
    _history,
    jsonEncode([for (final document in documents.take(historyLength)) document.toJson()]),
  );
}

/// Where the documents are saved until another folder is chosen, and always on phones: the app's own Documents folder,
/// and on Windows and Linux a Yangi alifbo folder in the person's Documents.
Future<Directory> defaultSaveFolder() async {
  final documents = await getApplicationDocumentsDirectory();
  return Platform.isWindows || Platform.isLinux
      ? Directory('${documents.path}${Platform.pathSeparator}Yangi alifbo')
      : documents;
}

/// Shows the files or folders at `paths` in Finder, selected, or opens the folder of the first one in Explorer or the
/// Linux file manager.
Future<void> revealInFileManager(List<String> paths) async {
  if (paths.isEmpty) return;
  // A sandboxed app may not have Finder open a folder, only reveal what is in it (macos/Runner/MainFlutterWindow.swift).
  if (Platform.isMacOS) return _finder.invokeMethod('reveal', paths);
  final first = paths.first;
  if (Platform.isWindows) {
    await Process.run('explorer.exe', FileSystemEntity.isFileSync(first) ? ['/select,', first] : [first]);
    return;
  }
  final folder = FileSystemEntity.isDirectorySync(first) ? first : File(first).parent.path;
  try {
    await launchUrl(Uri.directory(folder));
  } on PlatformException {
    // The Linux file manager opens folders as links; there is nothing else to try.
  }
}

/// Offers the files at `paths` to other apps through the share sheet, which points at `origin` on an iPad. This is how
/// a phone gets the documents out of the app: to Files, Word, a chat or mail.
Future<void> shareFiles(List<String> paths, Rect origin) async {
  await SharePlus.instance.share(
    ShareParams(files: [for (final path in paths) XFile(path)], sharePositionOrigin: origin),
  );
}

/// A short way to write `folder` for people: "App documents" for the app's own Documents folder, and the home folder
/// as ~.
String describeFolder(Directory folder, {required bool isDefault}) {
  if (isDefault && !Platform.isWindows && !Platform.isLinux) return 'App documents';
  // In the macOS sandbox, HOME is the app's container; the person's home is the folder that holds Library/Containers.
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) return folder.path;
  final container = home.indexOf('/Library/Containers/');
  final realHome = container == -1 ? home : home.substring(0, container);
  return folder.path.startsWith(realHome) ? '~${folder.path.substring(realHome.length)}' : folder.path;
}

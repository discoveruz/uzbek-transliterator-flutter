import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let finder = FlutterMethodChannel(
      name: "yangi_alifbo/finder", binaryMessenger: flutterViewController.engine.binaryMessenger)
    finder.setMethodCallHandler { call, result in
      switch call.method {
      // Shows files in Finder, selected. A sandboxed app may not ask Finder to open a folder, but may reveal what is
      // in it. The paths are resolved first: the sandbox's Downloads, for one, is a link to the real one.
      case "reveal":
        let paths = call.arguments as? [String] ?? []
        NSWorkspace.shared.activateFileViewerSelecting(
          paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() })
        result(nil)
      // A bookmark that lets the app back into a folder chosen in the open panel after it restarts.
      case "bookmark":
        let url = URL(fileURLWithPath: call.arguments as? String ?? "")
        let bookmark = try? url.bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        result(bookmark.map { FlutterStandardTypedData(bytes: $0) })
      // Opens the folder a bookmark is for, for as long as the app runs, and gives its path; nil when it is gone.
      case "access":
        guard let data = (call.arguments as? FlutterStandardTypedData)?.data else { return result(nil) }
        var stale = false
        guard
          let url = try? URL(
            resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
          url.startAccessingSecurityScopedResource()
        else { return result(nil) }
        result(url.path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

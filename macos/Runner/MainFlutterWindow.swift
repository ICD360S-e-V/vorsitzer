import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Prevent screenshots and screen capture
    // sharingType = .none excludes window from screen capture and screenshots
    self.sharingType = .none

    super.awakeFromNib()
  }

  // Fix Flutter macOS keyboard bug: force FlutterView to become first responder
  // when window becomes key (gains focus). This prevents keyboard input from
  // stopping after hot restart, window focus changes, or native dialog usage.
  override func becomeKey() {
    super.becomeKey()
    if let flutterVC = self.contentViewController as? FlutterViewController {
      DispatchQueue.main.async {
        flutterVC.view.window?.makeFirstResponder(flutterVC.view)
      }
    }
  }
}

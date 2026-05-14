import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private var notificationChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Setup notification center delegate FIRST
    let center = UNUserNotificationCenter.current()
    center.delegate = self

    // Request notification permissions
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        NSLog("Notification permission error: \(error)")
      }
      NSLog("Notification permission granted: \(granted)")
    }

    // Setup MethodChannel for native notifications
    // mainFlutterWindow is available here because MainFlutterWindow.awakeFromNib() already ran
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      NSLog("MethodChannel setup: FlutterViewController found")
      notificationChannel = FlutterMethodChannel(
        name: "de.icd360sev.vorsitzer/notifications",
        binaryMessenger: controller.engine.binaryMessenger
      )

      notificationChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "showNotification":
          if let args = call.arguments as? [String: Any],
             let title = args["title"] as? String,
             let body = args["body"] as? String {
            let payload = args["payload"] as? String
            NSLog("MethodChannel: showNotification called - \(title)")
            self?.showNativeNotification(title: title, body: body, payload: payload)
            result(true)
          } else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing title or body", details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    } else {
      NSLog("MethodChannel setup FAILED: mainFlutterWindow or FlutterViewController not available")
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Show notifications even when app is in foreground
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    NSLog("willPresent called - delivering foreground notification")
    if #available(macOS 12.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.sound, .badge])
    }
  }

  // Handle notification click - send payload back to Flutter
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    let payload = response.notification.request.content.userInfo["payload"] as? String ?? ""
    NSLog("Notification clicked: \(response.notification.request.content.title) payload: \(payload)")

    // Bring app to foreground
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
    }

    // Send click event to Flutter
    if !payload.isEmpty {
      notificationChannel?.invokeMethod("onNotificationClicked", arguments: payload)
    }

    completionHandler()
  }

  // Show native macOS notification
  private func showNativeNotification(title: String, body: String, payload: String? = nil) {
    NSLog("showNativeNotification: \(title) - \(body) payload: \(payload ?? "nil")")

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let payload = payload {
      content.userInfo = ["payload": payload]
    }

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil // Deliver immediately
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        NSLog("Notification add error: \(error)")
      } else {
        NSLog("Notification added successfully")
      }
    }
  }
}

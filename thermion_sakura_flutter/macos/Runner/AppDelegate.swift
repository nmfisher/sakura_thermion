import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var mouseCaptured = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "sakura_thermion/mouse_capture",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "capture":
        self.setMouseCaptured(true)
        result(nil)
      case "release":
        self.setMouseCaptured(false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setMouseCaptured(_ captured: Bool) {
    guard captured != mouseCaptured else { return }
    mouseCaptured = captured
    CGAssociateMouseAndMouseCursorPosition(boolean_t(captured ? 0 : 1))
    if captured {
      NSCursor.hide()
    } else {
      NSCursor.unhide()
    }
  }

  override func applicationDidResignActive(_ notification: Notification) {
    setMouseCaptured(false)
    super.applicationDidResignActive(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

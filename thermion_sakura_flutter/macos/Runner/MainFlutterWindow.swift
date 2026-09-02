import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var mouseCaptureChannel: FlutterMethodChannel?
  private var mouseCaptured = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    mouseCaptureChannel = FlutterMethodChannel(
      name: "sakura_thermion/mouse_capture",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    mouseCaptureChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "window_gone", message: "Window was released", details: nil))
        return
      }
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidResignActive),
      name: NSApplication.didResignActiveNotification,
      object: nil)

    super.awakeFromNib()
  }

  @objc private func applicationDidResignActive(_ notification: Notification) {
    setMouseCaptured(false)
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

  deinit {
    setMouseCaptured(false)
    NotificationCenter.default.removeObserver(self)
  }
}

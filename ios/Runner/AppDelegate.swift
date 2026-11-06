import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 实时活动（灵动岛 / 锁屏）通道：手工注册，无需额外 pod。
    if let registrar = engineBridge.pluginRegistry
      .registrar(forPlugin: "LiveActivityPlugin") {
      LiveActivityPlugin.register(with: registrar)
    }
    // 目录扫描导入的 security-scoped 访问通道（Dart 侧 kele_music/local_audio_ios）。
    if let registrar = engineBridge.pluginRegistry
      .registrar(forPlugin: "LocalAudioFolderPlugin") {
      LocalAudioFolderPlugin.register(with: registrar)
    }
  }
}

/// iOS 目录选择 + security-scoped 访问。
/// iOS 无法像 Android SAF 那样用 dart:io 读取 content:// 树，但目录选择器
/// 会返回真实的文件系统 URL；原生侧调用 startAccessingSecurityScopedResource()
/// 后，Dart 侧即可用 dart:io 递归遍历该目录。
final class LocalAudioFolderPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pickResult: FlutterResult?
  private var scopedURL: URL?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kele_music/local_audio_ios",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(
      LocalAudioFolderPlugin(), channel: channel)
  }

  func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "pickFolder":
      guard pickResult == nil else {
        result(FlutterError(
          code: "busy", message: "目录选择器已打开", details: nil))
        return
      }
      guard let host = topViewController() else {
        result(FlutterError(
          code: "no_activity", message: "无法打开目录选择器", details: nil))
        return
      }
      pickResult = result
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(
          forOpeningContentTypes: [UTType.folder], asCopy: false)
      } else {
        picker = UIDocumentPickerViewController(
          documentTypes: ["public.folder"], in: .open)
      }
      picker.delegate = self
      picker.allowsMultipleSelection = false
      host.present(picker, animated: true)

    case "beginFolderAccess":
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(
          code: "args", message: "缺少目录路径", details: nil))
        return
      }
      // 同一次选择流程里 URL 已持有授权，直接复用，避免重新构造 URL 丢权限。
      if let current = scopedURL, current.path == path {
        result(true)
        return
      }
      let url = URL(fileURLWithPath: path)
      let ok = url.startAccessingSecurityScopedResource()
      scopedURL?.stopAccessingSecurityScopedResource()
      scopedURL = ok ? url : nil
      result(ok)

    case "endFolderAccess":
      scopedURL?.stopAccessingSecurityScopedResource()
      scopedURL = nil
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let result = pickResult else { return }
    pickResult = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    let ok = url.startAccessingSecurityScopedResource()
    scopedURL?.stopAccessingSecurityScopedResource()
    scopedURL = ok ? url : nil
    result([
      "path": url.path,
      "name": url.lastPathComponent,
      "accessible": ok,
    ])
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pickResult?(nil)
    pickResult = nil
  }

  private func topViewController() -> UIViewController? {
    var root: UIViewController?
    if #available(iOS 13.0, *) {
      root = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .rootViewController
    }
    if root == nil {
      root = UIApplication.shared.keyWindow?.rootViewController
    }
    var top = root
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

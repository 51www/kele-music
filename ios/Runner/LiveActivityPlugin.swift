import ActivityKit
import Flutter
import UIKit

/// 向 Dart 暴露实时活动能力的 MethodChannel 插件。
/// 通道名与 Dart 侧 `LiveActivityBridge` 一致：`kele_music/live_activity`。
public final class LiveActivityPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "kele_music/live_activity",
            binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(
            LiveActivityPlugin(), channel: channel)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "isSupported":
            if #available(iOS 16.1, *) {
                let info = ActivityAuthorizationInfo()
                result([
                    "supported": info.areActivitiesEnabled,
                    "running": LiveActivityManager.shared.hasRunningActivity,
                ])
            } else {
                result([
                    "supported": false,
                    "running": false,
                    "reason": "Live Activities require iOS 16.1 or later",
                ])
            }

        case "update":
            guard #available(iOS 16.1, *) else {
                result(false)
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let payload = Self.makePayload(args)
            else {
                result(FlutterError(
                    code: "bad_args",
                    message: "Invalid Live Activity payload",
                    details: nil))
                return
            }
            LiveActivityManager.shared.update(payload) { error in
                if let error {
                    result(FlutterError(
                        code: "live_activity_failed",
                        message: error,
                        details: nil))
                } else {
                    result(nil)
                }
            }

        case "end":
            guard #available(iOS 16.1, *) else {
                result(nil)
                return
            }
            LiveActivityManager.shared.end { result(nil) }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.1, *)
    private static func makePayload(
        _ args: [String: Any]
    ) -> LiveActivityManager.Payload? {
        func intValue(_ key: String) -> Int {
            if let n = args[key] as? NSNumber { return n.intValue }
            return 0
        }
        func doubleMs(_ key: String) -> Double {
            if let n = args[key] as? NSNumber {
                return max(0, n.doubleValue / 1000.0)
            }
            return 0
        }
        func string(_ key: String) -> String {
            (args[key] as? String) ?? ""
        }
        let bytes = (args["artworkBytes"] as? FlutterStandardTypedData)?.data
        return LiveActivityManager.Payload(
            songId: intValue("songId"),
            title: string("title"),
            artist: string("artist"),
            album: string("album"),
            isPlaying: (args["isPlaying"] as? Bool) ?? false,
            position: doubleMs("positionMs"),
            duration: doubleMs("durationMs"),
            lyric: string("lyric"),
            translation: string("translation"),
            artworkData: bytes)
    }
}

import ActivityKit
import Foundation
import UIKit

/// ActivityKit 落地层：创建 / 更新 / 结束 Live Activity。
///
/// 仅 iOS 16.1+ 可用；系统关闭实时活动、用户关闭开关或 App Group 未配置时
/// 均不抛出致命错误，只是降级为「不显示」。
@available(iOS 16.1, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    struct Payload {
        let songId: Int
        let title: String
        let artist: String
        let album: String
        let isPlaying: Bool
        let position: Double
        let duration: Double
        let lyric: String
        let translation: String
        let artworkData: Data?
    }

    private var activity: Activity<KeleMusicLiveActivityAttributes>?

    private init() {
        adoptExistingActivity()
    }

    /// 进程重启后系统里可能还保留上一会话的活动，接续更新而不是重复创建。
    var hasRunningActivity: Bool {
        adoptExistingActivity()
        return activity != nil
    }

    private func adoptExistingActivity() {
        guard activity == nil else { return }
        activity = Activity<KeleMusicLiveActivityAttributes>.activities.first
    }

    // MARK: - 更新

    func update(_ payload: Payload, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                completion("Live Activities are disabled on this device")
                return
            }
            self.adoptExistingActivity()

            let artworkFile = self.prepareArtwork(
                data: payload.artworkData, songId: payload.songId)
            let state = KeleMusicLiveActivityAttributes.ContentState(
                isPlaying: payload.isPlaying,
                position: max(0, payload.position),
                duration: max(0, payload.duration),
                updatedAt: Date(),
                lyric: payload.lyric,
                translation: payload.translation,
                artworkFile: artworkFile
            )
            let attributes = KeleMusicLiveActivityAttributes(
                songId: payload.songId,
                title: payload.title,
                artist: payload.artist,
                album: payload.album
            )

            if let current = self.activity,
               current.attributes.songId == payload.songId {
                self.applyUpdate(current, state: state, completion: completion)
            } else {
                // 换歌：attributes 不可变，必须结束旧活动并新建。
                self.finish(self.activity)
                self.activity = nil
                self.requestNew(attributes: attributes, state: state,
                                completion: completion)
            }
        }
    }

    private func applyUpdate(
        _ activity: Activity<KeleMusicLiveActivityAttributes>,
        state: KeleMusicLiveActivityAttributes.ContentState,
        completion: @escaping (String?) -> Void
    ) {
        if #available(iOS 16.2, *) {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
                DispatchQueue.main.async { completion(nil) }
            }
        } else {
            Task {
                await activity.update(using: state)
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func requestNew(
        attributes: KeleMusicLiveActivityAttributes,
        state: KeleMusicLiveActivityAttributes.ContentState,
        completion: @escaping (String?) -> Void
    ) {
        do {
            let created: Activity<KeleMusicLiveActivityAttributes>
            if #available(iOS 16.2, *) {
                created = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil)
            } else {
                created = try Activity.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil)
            }
            self.activity = created
            completion(nil)
        } catch {
            completion(error.localizedDescription)
        }
    }

    // MARK: - 结束

    func end(completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            let running = Activity<KeleMusicLiveActivityAttributes>.activities
            Task {
                for item in running {
                    await item.end(dismissalPolicy: .immediate)
                }
                DispatchQueue.main.async {
                    self.activity = nil
                    completion()
                }
            }
        }
    }

    private func finish(_ activity: Activity<KeleMusicLiveActivityAttributes>?) {
        guard let activity else { return }
        Task { await activity.end(dismissalPolicy: .immediate) }
    }

    // MARK: - 封面落盘

    /// 把 Dart 下载好的封面字节缩放到 320px 内并写入 App Group 共享容器，
    /// Widget Extension 渲染时按文件名读取（Live Activity 不能直接加载网络图）。
    /// 没有新字节时复用同 songId 的既有文件。
    private func prepareArtwork(data: Data?, songId: Int) -> String {
        let fileName = "art-\(songId).jpg"
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: LiveActivityShared.appGroupId)
        else { return "" }
        let directory = container.appendingPathComponent(
            LiveActivityShared.artworkDirectory, isDirectory: true)
        let fileURL = directory.appendingPathComponent(fileName)

        guard let data, !data.isEmpty else {
            return FileManager.default.fileExists(atPath: fileURL.path)
                ? fileName : ""
        }

        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        guard let image = UIImage(data: data) else {
            // 不是可解码图片：原样落盘（Widget 端读不出会退回占位图）。
            try? data.write(to: fileURL, options: .atomic)
            return FileManager.default.fileExists(atPath: fileURL.path)
                ? fileName : ""
        }
        let maxSide: CGFloat = 320
        let side = max(image.size.width, image.size.height)
        let scale = side > maxSide ? maxSide / side : 1
        let target = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else {
            return ""
        }
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            cleanupArtwork(in: directory, keeping: fileName)
            return fileName
        } catch {
            return ""
        }
    }

    /// 只保留最近 12 张封面，避免共享容器随听歌数量无限增长。
    private func cleanupArtwork(in directory: URL, keeping: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let sorted = files.sorted {
            let l = try? $0.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate
            let r = try? $1.resourceValues(
                forKeys: [.contentModificationDateKey]).contentModificationDate
            return (l ?? .distantPast) < (r ?? .distantPast)
        }
        let overflow = max(0, sorted.count - 12)
        for url in sorted.prefix(overflow)
        where url.lastPathComponent != keeping {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

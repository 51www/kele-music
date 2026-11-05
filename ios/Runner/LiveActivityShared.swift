import ActivityKit
import Foundation

/// App 与 Widget Extension 共享的常量 / 活动属性定义。
///
/// ⚠️ 本文件必须同时加入 **Runner** 与 **KeleMusicLiveActivity**（Widget Extension）
/// 两个 target 的 Compile Sources，否则 ActivityKit 解码内容状态时会类型不匹配。
enum LiveActivityShared {
    /// 必须与两个 target 的 App Group 能力保持一致；改 bundle id 时同步修改。
    static let appGroupId = "group.com.example.keleMusicClient"

    /// App Group 共享容器内存放封面的子目录。
    static let artworkDirectory = "LiveActivityArtwork"

    /// 点击/长按实时活动后回到 App 的播放页（与 go_router 的 /now-playing 对应），
    /// 需要 Runner Info.plist 注册 `kele-music` URL Scheme。
    static let deepLinkURL = URL(string: "kele-music:///now-playing")!
}

/// 实时活动的不变属性（换歌时会结束旧活动并新建，故歌曲元信息放在 attributes）。
@available(iOS 16.1, *)
struct KeleMusicLiveActivityAttributes: ActivityAttributes {
    /// 可变内容：播放态、进度、当前歌词行、封面文件名。
    /// 注意不要放封面二进制（内容状态会被系统序列化且有体积限制）。
    struct ContentState: Codable, Hashable {
        var isPlaying: Bool
        var position: Double
        var duration: Double
        var updatedAt: Date
        var lyric: String
        var translation: String
        var artworkFile: String
    }

    var songId: Int
    var title: String
    var artist: String
    var album: String
}

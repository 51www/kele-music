import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

// 实时活动 UI：锁屏卡片 + 灵动岛（紧凑 / 展开 / 最小）。
// 目标部署版本必须为 iOS 16.1+（ActivityKit Live Activity 的下限）。
// 封面从 App Group 共享容器读取（文件名由 App 侧写入，避免在活动里加载网络图）。

private enum LiveActivityTheme {
    static let accent = Color(red: 240 / 255, green: 121 / 255, blue: 15 / 255)
    static let card = Color(red: 0.08, green: 0.07, blue: 0.06)
    static let secondary = Color.white.opacity(0.64)
}

private func artworkImage(for fileName: String) -> UIImage? {
    guard !fileName.isEmpty,
          let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: LiveActivityShared.appGroupId)
    else { return nil }
    let url = container
        .appendingPathComponent(LiveActivityShared.artworkDirectory, isDirectory: true)
        .appendingPathComponent(fileName)
    return UIImage(contentsOfFile: url.path)
}

private func clockText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}

private struct ArtworkView: View {
    let fileName: String
    let side: CGFloat

    var body: some View {
        Group {
            if let image = artworkImage(for: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.21, blue: 0.16),
                            Color(red: 0.13, green: 0.11, blue: 0.09),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.38, weight: .semibold))
                        .foregroundStyle(LiveActivityTheme.accent)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
    }
}

private typealias KeleMusicState = KeleMusicLiveActivityAttributes.ContentState

private struct ProgressLine: View {
    let state: KeleMusicState

    var body: some View {
        if state.isPlaying && state.duration > 0 {
            ProgressView(timerInterval: liveRange, countsDown: false)
                .progressViewStyle(.linear)
                .tint(LiveActivityTheme.accent)
        } else {
            ProgressView(value: min(max(state.position, 0), max(state.duration, 1)),
                         total: max(state.duration, 1))
                .progressViewStyle(.linear)
                .tint(LiveActivityTheme.accent)
        }
    }

    private var liveRange: ClosedRange<Date> {
        let end = state.updatedAt.addingTimeInterval(
            max(state.duration - state.position, 0.5))
        return state.updatedAt.addingTimeInterval(-max(state.position, 0))...end
    }
}

private struct ElapsedText: View {
    let state: KeleMusicState

    var body: some View {
        if state.isPlaying && state.duration > 0 {
            let end = state.updatedAt.addingTimeInterval(
                max(state.duration - state.position, 0.5))
            Text(timerInterval: state.updatedAt.addingTimeInterval(
                -max(state.position, 0))...end,
                 countsDown: false)
        } else {
            Text(clockText(state.position))
        }
    }
}

private struct LyricText: View {
    let state: KeleMusicState

    var body: some View {
        Text(state.lyric.isEmpty
             ? (state.isPlaying ? "正在播放" : "已暂停")
             : state.lyric)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(LiveActivityTheme.accent)
            .lineLimit(1)
    }
}

// MARK: - 锁屏卡片

private struct LockScreenView: View {
    let context: ActivityViewContext<KeleMusicLiveActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ArtworkView(fileName: context.state.artworkFile, side: 52)
                .overlay(alignment: .bottomTrailing) {
                    if !context.state.isPlaying {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(
                                Circle().fill(Color.black.opacity(0.55)))
                            .offset(x: 4, y: 4)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(context.attributes.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(LiveActivityTheme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: context.state.isPlaying
                          ? "waveform" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LiveActivityTheme.accent)
                }
                ProgressLine(state: context.state)
                    .frame(height: 3)
                    .padding(.top, 1)
                LyricText(state: context.state)
                if !context.state.translation.isEmpty {
                    Text(context.state.translation)
                        .font(.system(size: 11))
                        .foregroundStyle(LiveActivityTheme.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    ElapsedText(state: context.state)
                    Spacer()
                    Text(clockText(context.state.duration))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LiveActivityTheme.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .widgetURL(LiveActivityShared.deepLinkURL)
    }
}

// MARK: - 灵动岛

private struct IslandExpandedLeading: View {
    let context: ActivityViewContext<KeleMusicLiveActivityAttributes>

    var body: some View {
        ArtworkView(fileName: context.state.artworkFile, side: 46)
    }
}

private struct IslandTitle: View {
    let context: ActivityViewContext<KeleMusicLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.attributes.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(context.attributes.artist)
                .font(.system(size: 11))
                .foregroundStyle(LiveActivityTheme.secondary)
                .lineLimit(1)
        }
    }
}

private struct IslandBottom: View {
    let context: ActivityViewContext<KeleMusicLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                LyricText(state: context.state)
                Spacer(minLength: 4)
                ElapsedText(state: context.state)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LiveActivityTheme.secondary)
                Text(clockText(context.state.duration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LiveActivityTheme.secondary)
            }
            ProgressLine(state: context.state)
                .frame(height: 3)
        }
        .padding(.horizontal, 2)
        .widgetURL(LiveActivityShared.deepLinkURL)
    }
}

// MARK: - Widget

struct KeleMusicLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KeleMusicLiveActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(LiveActivityTheme.card)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandTitle(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying
                          ? "waveform" : "pause.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LiveActivityTheme.accent)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottom(context: context)
                }
            } compactLeading: {
                ArtworkView(fileName: context.state.artworkFile, side: 18)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying
                      ? "waveform" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiveActivityTheme.accent)
            } minimal: {
                ArtworkView(fileName: context.state.artworkFile, side: 16)
            }
            .widgetURL(LiveActivityShared.deepLinkURL)
            .keylineTint(LiveActivityTheme.accent)
        }
    }
}

@main
struct KeleMusicLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        KeleMusicLiveActivityWidget()
    }
}

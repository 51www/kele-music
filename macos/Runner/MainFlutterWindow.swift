import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    // 桌面化窗口：默认尺寸更像桌面 App（而非手机比例），并居中。
    windowFrame.size = NSSize(width: 1180, height: 800)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    // 隐藏标题栏文字与背景，内容铺满整窗（应用渐变透到交通灯之后），
    // 仍可用交通灯；窗口任意空白处可拖拽移动。
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.backgroundColor = .clear

    // 合理的最小尺寸，避免被拉成手机比例导致侧边栏拥挤。
    self.minSize = NSSize(width: 900, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

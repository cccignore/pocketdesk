import CoreGraphics
import Testing
@testable import SnugCore

@Suite("屏上一点处最上面的窗口 WindowStack")
struct WindowStackTests {
    /// 左边的 Snug 手机屏、右边的主屏（全局坐标，左上原点）
    private let phone = CGRect(x: -590, y: 0, width: 590, height: 1142)
    private let tray = CGRect(x: -590, y: 624, width: 590, height: 487)

    @Test("大半在这块屏外的窗口不算：分屏空间下它画在别的屏上，坐标跨过来的那截看不见（11-24 实测 Claude 的主窗口大半在主屏左边之外）")
    func skipsWindowsMostlyElsewhere() {
        let claude = CGRect(x: -1549, y: 45, width: 1512, height: 948)
        let windows: [(id: UInt32, frame: CGRect)] = [(1, claude), (2, tray)]
        #expect(WindowStack.topmost(at: CGPoint(x: -295, y: 870), on: phone, in: windows, separateSpaces: true, frame: \.frame)?.id == 2)
    }

    @Test("关掉了「显示器具有单独的空间」：跨屏的窗口两块屏上都画、都点得到，坐标盖过来的照常算最上面")
    func spansDisplays() {
        let claude = CGRect(x: -1549, y: 45, width: 1512, height: 948)
        let windows: [(id: UInt32, frame: CGRect)] = [(1, claude), (2, tray)]
        #expect(WindowStack.topmost(at: CGPoint(x: -295, y: 870), on: phone, in: windows, separateSpaces: false, frame: \.frame)?.id == 1)
    }

    @Test("大半在这块屏上的窗口照常算：盖在托盘上的 App 窗口是最上面的；这一点上没有窗口为 nil")
    func countsWindowsOnThisScreen() {
        let app = CGRect(x: -590, y: 30, width: 590, height: 900)
        let windows: [(id: UInt32, frame: CGRect)] = [(1, app), (2, tray)]
        #expect(WindowStack.topmost(at: CGPoint(x: -295, y: 870), on: phone, in: windows, separateSpaces: true, frame: \.frame)?.id == 1)
        #expect(WindowStack.topmost(at: CGPoint(x: -295, y: 1130), on: phone, in: windows, separateSpaces: true, frame: \.frame) == nil)
    }

    @Test("一大半才算：正好一半在这块屏上不算，多一点就算")
    func majority() {
        #expect(!CGRect(x: -100, y: 0, width: 200, height: 100).mostlyOn(CGRect(x: 0, y: 0, width: 500, height: 500)))
        #expect(CGRect(x: -99, y: 0, width: 200, height: 100).mostlyOn(CGRect(x: 0, y: 0, width: 500, height: 500)))
        #expect(!CGRect(x: 600, y: 0, width: 200, height: 100).mostlyOn(CGRect(x: 0, y: 0, width: 500, height: 500)))
    }
}

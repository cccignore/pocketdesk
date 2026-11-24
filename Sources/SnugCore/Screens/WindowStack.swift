// 屏上一点处最上面的窗口：点下去时核对点的是谁（关闭按钮、Snug 自己的面板）。
// 窗口服务器的列表按坐标给窗口的范围，分屏空间下一个窗口却只画在一块屏上：坐标跨到别的屏上的那截在那块屏上看不见，
// 点击也落不到它，却照样列着、排在那块屏的窗口前面（11-24 实测：Claude 的主窗口大半在主屏左边之外，坐标盖住左边的 Snug 屏，
// 屏上看不到它，点托盘照样点到托盘）。所以只认一大半在这块屏上的窗口。这只是近似：窗口归哪块屏系统不全按几何算。
// 系统设置里关掉「显示器具有单独的空间」时跨屏的窗口两块屏上都画、都点得到，不按屏筛
import CoreGraphics

public enum WindowStack {
    /// windows：窗口服务器给的屏上窗口，从前到后；frame 取它的范围（全局坐标）。这块屏上 point 处最上面的那个，没有为 nil。
    /// separateSpaces：开着「显示器具有单独的空间」（NSScreen.screensHaveSeparateSpaces）
    public static func topmost<W>(at point: CGPoint, on screen: CGRect, in windows: [W], separateSpaces: Bool, frame: (W) -> CGRect) -> W? {
        windows.first { frame($0).contains(point) && (!separateSpaces || frame($0).mostlyOn(screen)) }
    }
}

extension CGRect {
    /// 一大半（超过一半的面积）在 screen 里
    public func mostlyOn(_ screen: CGRect) -> Bool {
        let inside = intersection(screen)
        guard !inside.isNull, width > 0, height > 0 else { return false }
        return inside.width * inside.height * 2 > width * height
    }
}

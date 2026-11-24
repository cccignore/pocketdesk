// 点下去时核对点的是谁（关闭按钮、Snug 自己的面板）用的屏上窗口：问窗口服务器，从前到后，全局坐标左上原点。
// 指针不算：窗口服务器把指针当成光标层的一个小窗口，远控把指针挪到点的位置上，点的那一刻它正盖在那一点上
// （11-24 实测：手机上点 Snug 的键盘托盘，那一刻托盘前面是窗口服务器的一个 32×32 窗口），不去掉就以为点的是别人的窗口。
// 哪些窗口其实在别的屏上由调用方按屏筛（WindowStack）
import CoreGraphics
import Foundation

enum HitWindows {
    struct Window {
        let id: UInt32
        let pid: Int32?
        let frame: CGRect
    }

    static func frontToBack() -> [Window] {
        let cursor = Int(CGWindowLevelForKey(.cursorWindow))
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return (list ?? []).compactMap { info in
            guard ((info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0) < cursor,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return Window(id: id, pid: (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, frame: frame)
        }
    }
}

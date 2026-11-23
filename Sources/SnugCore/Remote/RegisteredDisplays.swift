// 只在启动时读一次显示器的远控（CrossDesk）按当时登记的几块显示器分位置推流，某个位置原来那块不在了就改抓此刻显示器列表里
// 同一序号上的那块（CrossDesk 的 screen_capturer_sck_impl.mm）。据此判断 Snug 此刻在线的屏它切不切得到，切不到就要重启它
import Foundation

public enum RegisteredDisplays {
    /// Snug 此刻在线的屏里有没有它切不到的：登记过编号的切得到；没登记过的（之后才建、Snug 重启后换了编号）要正好落在
    /// 一个原来那块已经不在的位置上（此刻列表里同一序号）。之后接上的外接屏、随航不是 Snug 的屏，只在占了位置时影响判断。
    /// online 按系统列出显示器的顺序（CGGetOnlineDisplayList），当它和 CrossDesk 用的 ScreenCaptureKit 列的顺序一样（模拟器实测
    /// Snug 重启后 1 号位补上的正是列表里的第 2 块）
    public static func misses(_ registered: [DisplayID], snug: Set<DisplayID>, online: [DisplayID]) -> Bool {
        let filled = Set(registered.indices.compactMap { slot -> DisplayID? in
            guard !online.contains(registered[slot]), slot < online.count else { return nil }
            return online[slot]
        })
        return snug.contains { !registered.contains($0) && !filled.contains($0) }
    }
}

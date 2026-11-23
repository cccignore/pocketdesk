// 只在启动时读一次显示器的远控（CrossDesk）按当时登记的几块显示器分位置推流，某个位置原来那块不在了就改抓列表里同一位置上的屏
// （CrossDesk 的 screen_capturer_sck_impl.mm）。据此判断 Snug 此刻在线的屏它切不切得到，切不到就要重启它
import Foundation

public enum RegisteredDisplays {
    /// Snug 此刻在线的屏里有没有它切不到的：登记过编号的切得到；没登记过的（之后才建、Snug 重启后换了编号）要占一个
    /// 原来那块已经不在的位置，不够分就有切不到的。之后接上的外接屏、随航不是 Snug 的屏，不算。
    /// 位置按系统列出显示器的顺序补，顺序变了（换了主屏、几块屏先后重建）时可能补错，这里看不出来
    public static func misses(_ registered: [DisplayID], snug: Set<DisplayID>, online: Set<DisplayID>) -> Bool {
        snug.subtracting(registered).count > Set(registered).subtracting(online).count
    }
}

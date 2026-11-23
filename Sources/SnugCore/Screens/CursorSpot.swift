// 换档时光标放哪：屏一变矮，系统把落在新尺寸外的光标夹到底边，macOS 当成指针顶到了这块屏的底边，
// 把程序坞挪到 Snug 的屏上（常显程序坞时实测，11-24：点小横条上的键盘键铺回整屏，590 换回 540 宽，程序坞跟着过来盖住小横条）。
// 换档前先按它在屏上的相对位置挪进新尺寸里，换档后再按新屏的边界放回同一相对位置。坐标都是全局坐标，左上原点
import CoreGraphics

/// 光标在一块屏上的相对位置（0 到 1）
public struct CursorSpot: Equatable, Sendable {
    let relative: CGPoint
    /// 换档前的屏范围
    let bounds: CGRect

    /// 光标不在这块屏上交回 nil：换档不碰它
    public init?(_ cursor: CGPoint, on bounds: CGRect) {
        guard bounds.contains(cursor), bounds.width > 0, bounds.height > 0 else { return nil }
        relative = CGPoint(x: (cursor.x - bounds.minX) / bounds.width, y: (cursor.y - bounds.minY) / bounds.height)
        self.bounds = bounds
    }

    /// 换档前挪到这里：同一相对位置按新尺寸算，从屏左上角量起，新旧两种尺寸下都在屏内，换档时没有可夹的。
    /// 屏变大时就是原处
    public func beforeSwitch(to size: CGSize) -> CGPoint {
        let common = CGSize(width: min(bounds.width, size.width), height: min(bounds.height, size.height))
        guard common != bounds.size else { return place(in: bounds, sized: bounds.size) }
        return place(in: CGRect(origin: bounds.origin, size: common), sized: size)
    }

    /// 换档后挪到这里：新屏上的同一相对位置
    public func afterSwitch(in newBounds: CGRect) -> CGPoint {
        place(in: newBounds, sized: newBounds.size)
    }

    /// 按 size 算相对位置，落在 area 里、离右边和底边至少一个点（贴着底边就是在招程序坞）
    private func place(in area: CGRect, sized size: CGSize) -> CGPoint {
        CGPoint(x: area.minX + min(relative.x * size.width, area.width - 1),
                y: area.minY + min(relative.y * size.height, area.height - 1))
    }
}

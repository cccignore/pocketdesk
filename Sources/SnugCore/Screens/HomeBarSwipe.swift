// 底部小横条上的滑动：往上滑回 App 资源库，左右滑切回这块屏上一个窗口（和 iPhone 底部横条左右滑切 App 一样）。
// 手势翻译把单指滑动变成滚动，横条按一笔里手指实际划过的位移认方向（松手后的惯性不算），一笔只认一次。
// 方向按角度分：比水平陡过约 27°（往上的量不小于横向的一半）算往上，平过这个算左右，斜着往上滑照旧回资源库。
// 纯逻辑，横条的视图在 Snug 的 ScreenWindows（HomeBarView）
import CoreGraphics

public struct HomeBarSwipe: Sendable {
    public enum Action: Equatable, Sendable {
        case showList
        case switchBack
    }

    /// 基准宽度下往上滑过这么多点算数
    static let upDistance: CGFloat = 12
    /// 左右滑过这么多点算数：比往上的长，横条只有一指高，往上那一点不该被左右滑带出来
    static let sideDistance: CGFloat = 40

    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var recognized = false

    public init() {}

    /// 一笔滚动开始（phase began）
    public mutating func began() {
        dx = 0
        dy = 0
        recognized = false
    }

    /// 一笔里的一下：scrollingDelta，手指往上走 dy 是负的。scale：这一档比基准宽度宽几倍（ScreenFit.scale），距离跟着放大。
    /// momentum：松手后的惯性那几下，不算（轻轻一拨带出的惯性能走一百多点，算上它左右滑就没有门槛了）
    public mutating func scroll(dx: CGFloat, dy: CGFloat, scale: CGFloat, momentum: Bool = false) -> Action? {
        guard !recognized, !momentum else { return nil }
        self.dx += dx
        self.dy += dy
        let up = -self.dy, side = abs(self.dx)
        if up >= Self.upDistance * scale, up * 2 >= side {
            recognized = true
            return .showList
        }
        if side >= Self.sideDistance * scale, side > abs(self.dy) * 2 {
            recognized = true
            return .switchBack
        }
        return nil
    }
}

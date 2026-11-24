import CoreGraphics
import Testing
@testable import SnugCore

@Suite("小横条上的滑动 HomeBarSwipe")
struct HomeBarSwipeTests {
    /// 一笔滚动：每一下的 (dx, dy)，手指往上走 dy 是负的；momentum 是松手后的惯性那几下。交回这一笔认出的动作
    private func stroke(_ steps: [(CGFloat, CGFloat)], momentum: [(CGFloat, CGFloat)] = [], scale: CGFloat = 1,
                        on swipe: inout HomeBarSwipe) -> [HomeBarSwipe.Action] {
        swipe.began()
        return steps.compactMap { swipe.scroll(dx: $0.0, dy: $0.1, scale: scale) }
            + momentum.compactMap { swipe.scroll(dx: $0.0, dy: $0.1, scale: scale, momentum: true) }
    }

    @Test("往上滑过 12 点：回 App 资源库，一笔只认一次")
    func upShowsList() {
        var swipe = HomeBarSwipe()
        #expect(stroke([(0, -5), (1, -8), (0, -10), (0, -10)], momentum: [(0, -30), (0, -20)], on: &swipe) == [.showList])
    }

    @Test("斜着往上滑（比水平陡过约 27°）：照旧回资源库，不当成左右滑")
    func diagonalUpShowsList() {
        var swipe = HomeBarSwipe()
        #expect(stroke([(8, -6), (8, -6), (8, -6), (8, -6), (8, -6), (8, -6)], on: &swipe) == [.showList])
    }

    @Test("惯性不算：手指只左右划了 20 点、惯性又走了一百多点，不切；往上轻轻一拨不到 12 点也不回资源库")
    func momentumIgnored() {
        var swipe = HomeBarSwipe()
        #expect(stroke([(10, 0), (10, 0)], momentum: [(40, 0), (40, 0), (40, 0), (30, 0)], on: &swipe).isEmpty)
        #expect(stroke([(0, -4), (0, -4)], momentum: [(0, -20), (0, -20)], on: &swipe).isEmpty)
    }

    @Test("左右滑过 40 点：切回上一个窗口，往哪边滑都一样；一笔只认一次")
    func sidewaysSwitchesBack() {
        var swipe = HomeBarSwipe()
        #expect(stroke([(15, -2), (15, -3), (15, -2), (20, 0)], on: &swipe) == [.switchBack])
        #expect(stroke([(-25, 1), (-25, 0), (-25, 0)], on: &swipe) == [.switchBack])
    }

    @Test("左右滑时手指往上漂了十几点：横向为主，不回资源库")
    func sidewaysWithUpwardDrift() {
        var swipe = HomeBarSwipe()
        #expect(stroke([(10, -4), (12, -5), (12, -5), (12, -2)], on: &swipe) == [.switchBack])
    }

    @Test("往下滑、滑得太短：都不认")
    func tooShortOrDown() {
        var swipe = HomeBarSwipe()
        #expect(stroke([(0, 8), (0, 20)], on: &swipe).isEmpty)
        #expect(stroke([(10, -1), (10, 0)], on: &swipe).isEmpty)
    }

    @Test("宽一档的屏上（scale 1.1）距离跟着放大：手机上划着一样长")
    func scaled() {
        var swipe = HomeBarSwipe()
        #expect(stroke([(42, 0)], scale: 1.1, on: &swipe).isEmpty)
        #expect(stroke([(45, 0)], scale: 1.1, on: &swipe) == [.switchBack])
        #expect(stroke([(0, -12)], scale: 1.1, on: &swipe).isEmpty)
    }
}

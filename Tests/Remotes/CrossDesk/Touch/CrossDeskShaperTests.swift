import CoreGraphics
import Foundation
import RemoteCrossDesk
import SnugCore
import Testing

private let phone = TouchRegion(frame: CGRect(x: 0, y: 0, width: 540, height: 950), scale: 1)
private let p = CGPoint(x: 100, y: 300)

private func event(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ t: Double) -> PointerEvent {
    PointerEvent(kind, at: CGPoint(x: x, y: y), time: t)
}

private func commands(_ step: TouchStep) -> [TouchCommand] {
    step.effects.compactMap { if case .command(let c, _) = $0 { c } else { nil } }
}

private func phases(_ step: TouchStep) -> [ScrollPhase] {
    commands(step).compactMap { if case .scroll(let s) = $0 { s.phase } else { nil } }
}

/// CrossDesk 的 iPhone 客户端（绝对位置模式）发来的形态，取自它的源码（apps/ios/CrossDeskMobile/Input/RemoteTouchInputView.swift）：
/// 点一下 = 移动、按下、抬起几乎同时到；单指滑动 = 只有不按键的移动；按住 0.35 秒才发按下，之后的移动带着左键（拖动）
@Suite("CrossDesk 手势整理")
struct CrossDeskShaperTests {
    @Test("接管左键三种和不按键的移动")
    func kinds() {
        #expect(CrossDeskShaper().kinds == [.leftDown, .leftDrag, .leftUp, .move])
    }

    @Test("不按键的移动拼成一笔，每一下都等下一个事件来了才交出去（紧跟着按下的那一下是点按的前导，不算滑动）：第一下当按下，之后当拖动；停手超过收尾时间补上最后一下和抬起，抬起记在最后一下的时刻（估甩速要用）")
    func movesStitchIntoStroke() {
        var shaper = CrossDeskShaper()
        #expect(shaper.shape(event(.move, 100, 300, 1)).isEmpty)
        #expect(shaper.shape(event(.move, 100, 340, 1.02)) == [ShapedInput(TouchInput(.press, at: p, time: 1, synthetic: true), fromCurrent: false)])
        #expect(shaper.shape(event(.move, 100, 380, 1.04)) == [ShapedInput(TouchInput(.drag, at: CGPoint(x: 100, y: 340), time: 1.02, synthetic: true), fromCurrent: false)])
        #expect(shaper.deadline == 1.04 + CrossDeskShaper.strokeTimeout)
        #expect(shaper.expire(now: 1.05).isEmpty)
        let last = CGPoint(x: 100, y: 380)
        #expect(shaper.expire(now: 1.04 + CrossDeskShaper.strokeTimeout) == [
            ShapedInput(TouchInput(.drag, at: last, time: 1.04, synthetic: true), fromCurrent: false),
            ShapedInput(TouchInput(.release, at: last, time: 1.04, synthetic: true), fromCurrent: false),
        ])
        #expect(shaper.deadline == nil)
        // 孤零零的一下移动（两指点右键前、悬停一下）到点就扔掉，什么都不交
        _ = shaper.shape(event(.move, 100, 300, 3))
        #expect(shaper.expire(now: 3 + CrossDeskShaper.strokeTimeout).isEmpty)
        #expect(shaper.deadline == nil)
    }

    @Test("按下前先收掉没收尾的那一笔（点一下前那下移动），按下的时刻往前推 0.35 秒，还原手指真正落下的时刻；按住时的移动当拖动")
    func pressBackdatesAndFinishesStroke() {
        var shaper = CrossDeskShaper()
        _ = shaper.shape(event(.move, 100, 300, 5))
        #expect(shaper.shape(event(.leftDown, 100, 300, 5.001)) == [
            ShapedInput(TouchInput(.press, at: p, time: 5.001 - CrossDeskShaper.holdDelay), fromCurrent: true),
        ])
        #expect(shaper.deadline == nil)
        #expect(shaper.shape(event(.move, 100, 320, 5.2)) == [ShapedInput(TouchInput(.drag, at: CGPoint(x: 100, y: 320), time: 5.2), fromCurrent: true)])
        #expect(shaper.shape(event(.leftDrag, 100, 330, 5.3)).map(\.input) == [TouchInput(.drag, at: CGPoint(x: 100, y: 330), time: 5.3)])
        #expect(shaper.shape(event(.leftUp, 100, 330, 5.4)).map(\.input) == [TouchInput(.release, at: CGPoint(x: 100, y: 330), time: 5.4)])
        // 松手后的移动又是新的一笔
        _ = shaper.shape(event(.move, 100, 330, 6))
        #expect(shaper.shape(event(.move, 100, 360, 6.02)).map(\.input.synthetic) == [true])
    }

    @Test("滑到一半按下（滑完马上点）：先把已经滑的那一笔收掉（抬起记在点按前导之前的最后一下），点按的前导不算进滑动")
    func pressFinishesStartedStroke() {
        var shaper = CrossDeskShaper()
        _ = shaper.shape(event(.move, 100, 300, 1))
        _ = shaper.shape(event(.move, 100, 340, 1.02))
        _ = shaper.shape(event(.move, 400, 900, 1.05))   // 点按的前导：在点的地方
        #expect(shaper.shape(event(.leftDown, 400, 900, 1.051)) == [
            ShapedInput(TouchInput(.release, at: CGPoint(x: 100, y: 340), time: 1.02, synthetic: true), fromCurrent: false),
            ShapedInput(TouchInput(.press, at: CGPoint(x: 400, y: 900), time: 1.051 - CrossDeskShaper.holdDelay), fromCurrent: true),
        ])
    }

    @Test("端到端：点一下是点击（补发 CrossDesk 的按下、抬起）；不按键的移动原样放行（指针跟着手指走）")
    func tapClicks() {
        var pipeline = TouchPipeline(shapers: [CrossDeskShaper()])
        #expect(pipeline.handle(event(.move, 100, 300, 0), from: 0, regions: [phone]).passOriginal)
        let down = pipeline.handle(event(.leftDown, 100, 300, 0.001), from: 0, regions: [phone])
        #expect(down.effects.contains(.hold))
        #expect(commands(pipeline.handle(event(.leftUp, 100, 300, 0.002), from: 0, regions: [phone])) == [.replayPress, .replayCurrent])
    }

    @Test("端到端：按住 0.5 秒（CrossDesk 在 0.35 秒时发按下）松手是右键；不到 0.5 秒松手仍是点击")
    func holdRightClicks() {
        var pipeline = TouchPipeline(shapers: [CrossDeskShaper()])
        _ = pipeline.handle(event(.move, 100, 300, 0.35), from: 0, regions: [phone])
        _ = pipeline.handle(event(.leftDown, 100, 300, 0.35), from: 0, regions: [phone])
        #expect(commands(pipeline.handle(event(.leftUp, 100, 300, 0.6), from: 0, regions: [phone])) == [.rightClick(at: p)])

        _ = pipeline.handle(event(.move, 100, 300, 2.35), from: 0, regions: [phone])
        _ = pipeline.handle(event(.leftDown, 100, 300, 2.35), from: 0, regions: [phone])
        #expect(commands(pipeline.handle(event(.leftUp, 100, 300, 2.45), from: 0, regions: [phone])) == [.replayPress, .replayCurrent])
    }

    @Test("端到端：按住够久再拖是选择（补发按下和当前拖动，之后原样放行）")
    func holdThenDragSelects() {
        var pipeline = TouchPipeline(shapers: [CrossDeskShaper()])
        _ = pipeline.handle(event(.move, 100, 300, 0.35), from: 0, regions: [phone])
        _ = pipeline.handle(event(.leftDown, 100, 300, 0.35), from: 0, regions: [phone])
        #expect(commands(pipeline.handle(event(.leftDrag, 100, 340, 0.55), from: 0, regions: [phone])) == [.replayPress, .replayCurrent])
        #expect(pipeline.handle(event(.leftDrag, 100, 380, 0.6), from: 0, regions: [phone]).passOriginal)
        #expect(pipeline.handle(event(.leftUp, 100, 380, 0.7), from: 0, regions: [phone]).passOriginal)
    }

    @Test("端到端：单指滑动是滚动（晚一个事件开始），甩一下停手后带惯性；手机屏外的移动原样放行")
    func swipeScrollsAndCoasts() {
        var pipeline = TouchPipeline(shapers: [CrossDeskShaper()])
        #expect(phases(pipeline.handle(event(.move, 100, 300, 0), from: 0, regions: [phone])).isEmpty)
        #expect(phases(pipeline.handle(event(.move, 100, 330, 0.02), from: 0, regions: [phone])).isEmpty)
        #expect(phases(pipeline.handle(event(.move, 100, 360, 0.04), from: 0, regions: [phone])) == [.began, .changed])
        for i in 3...5 { _ = pipeline.handle(event(.move, 100, 300 + 30 * Double(i), 0.02 * Double(i)), from: 0, regions: [phone]) }
        let deadline = try! #require(pipeline.deadline)
        #expect(phases(pipeline.expire(now: deadline, regions: [phone])) == [.changed, .ended])
        #expect(pipeline.isCoasting)

        var outside = TouchPipeline(shapers: [CrossDeskShaper()])
        #expect(outside.handle(event(.move, 2000, 300, 0), from: 0, regions: [phone]).passOriginal)
        #expect(outside.handle(event(.move, 2000, 360, 0.02), from: 0, regions: [phone]).passOriginal)
    }

    @Test("端到端：惯性中点一下只是停住，不点到还在滚的内容（和 iPhone 一样）")
    func tapDuringCoastOnlyStops() {
        var pipeline = TouchPipeline(shapers: [CrossDeskShaper()])
        for i in 0...5 { _ = pipeline.handle(event(.move, 100, 300 + 30 * Double(i), 0.02 * Double(i)), from: 0, regions: [phone]) }
        _ = pipeline.expire(now: try! #require(pipeline.deadline), regions: [phone])
        #expect(pipeline.isCoasting)
        _ = pipeline.handle(event(.move, 200, 500, 0.5), from: 0, regions: [phone])
        let down = pipeline.handle(event(.leftDown, 200, 500, 0.501), from: 0, regions: [phone])
        // 按下只发惯性结束，不扣不补别的
        #expect(commands(down).map { if case .scroll(let s) = $0 { s.momentum == .end } else { false } } == [true])
        #expect(!pipeline.isCoasting)
        #expect(commands(pipeline.handle(event(.leftUp, 200, 500, 0.502), from: 0, regions: [phone])).isEmpty)
    }

    @Test("端到端：滑完马上点（还没到收尾时间）：滚动不跳到点的地方，惯性按真正滑的速度，这一点只是停住惯性")
    func tapRightAfterSwipeDoesNotJump() {
        var pipeline = TouchPipeline(shapers: [CrossDeskShaper()])
        var deltas: [Double] = []
        for i in 0...5 {
            let step = pipeline.handle(event(.move, 100, 300 + 30 * Double(i), 0.02 * Double(i)), from: 0, regions: [phone])
            deltas += commands(step).compactMap { if case .scroll(let s) = $0 { s.deltaY } else { nil } }
        }
        let lead = pipeline.handle(event(.move, 400, 900, 0.15), from: 0, regions: [phone])
        deltas += commands(lead).compactMap { if case .scroll(let s) = $0 { s.deltaY } else { nil } }
        let down = pipeline.handle(event(.leftDown, 400, 900, 0.151), from: 0, regions: [phone])
        deltas += commands(down).compactMap { if case .scroll(let s) = $0 { s.deltaY } else { nil } }
        // 滑的每一步最多 30 点：跳到点的地方会是几百点的一步
        #expect(deltas.allSatisfy { abs($0) <= 31 })
        #expect(commands(pipeline.handle(event(.leftUp, 400, 900, 0.152), from: 0, regions: [phone])).isEmpty)
    }
}

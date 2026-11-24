import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

private let phone = TouchRegion(frame: CGRect(x: 0, y: 0, width: 540, height: 950), scale: 1)

private func event(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ t: Double) -> PointerEvent {
    PointerEvent(kind, at: CGPoint(x: x, y: y), time: t)
}

private func scrollPhases(_ step: TouchStep) -> [ScrollPhase] {
    step.effects.compactMap { if case .command(.scroll(let s), _) = $0 { s.phase } else { nil } }
}

/// 假的整理器：不按键的移动拼成一笔（第一下当按下），按下时先把没收尾的那笔收掉；到点收尾。
/// 只用来钉住分派的顺序，真的整理器在各家远控的目标里
private struct StitchingShaper: TouchShaper {
    let kinds: Set<PointerEvent.Kind> = [.leftDown, .leftDrag, .leftUp, .move]
    private var last: (point: CGPoint, time: TimeInterval)?

    var deadline: TimeInterval? { last.map { $0.time + 0.125 } }

    mutating func shape(_ event: PointerEvent) -> [ShapedInput] {
        switch event.kind {
        case .move:
            let kind: TouchInput.Kind = last == nil ? .press : .drag
            last = (event.location, event.time)
            return [ShapedInput(TouchInput(kind, at: event.location, time: event.time, synthetic: true), fromCurrent: true)]
        case .leftDown:
            return finish() + [ShapedInput(TouchInput(.press, at: event.location, time: event.time), fromCurrent: true)]
        case .leftDrag:
            return [ShapedInput(TouchInput(.drag, at: event.location, time: event.time), fromCurrent: true)]
        case .leftUp:
            return [ShapedInput(TouchInput(.release, at: event.location, time: event.time), fromCurrent: true)]
        }
    }

    mutating func expire(now: TimeInterval) -> [ShapedInput] {
        guard let deadline, now >= deadline else { return [] }
        return finish()
    }

    private mutating func finish() -> [ShapedInput] {
        guard let last else { return [] }
        self.last = nil
        return [ShapedInput(TouchInput(.release, at: last.point, time: last.time, synthetic: true), fromCurrent: false)]
    }
}

@Suite("手势分派 TouchPipeline")
struct TouchPipelineTests {
    @Test("原样直通：只接管左键的按下、拖动、抬起（和以前的事件监听一样），不发抬起的整理器才要超时")
    func directShaper() {
        var shaper = DirectShaper()
        #expect(shaper.kinds == [.leftDown, .leftDrag, .leftUp])
        #expect(shaper.deadline == nil)
        #expect(shaper.shape(event(.leftDown, 1, 2, 3)) == [ShapedInput(TouchInput(.press, at: CGPoint(x: 1, y: 2), time: 3), fromCurrent: true)])
        #expect(shaper.shape(event(.leftDrag, 1, 2, 3)).map(\.input.kind) == [.drag])
        #expect(shaper.shape(event(.leftUp, 1, 2, 3)).map(\.input.kind) == [.release])
        #expect(shaper.expire(now: 99).isEmpty)
    }

    @Test("原样直通时和以前的分派一样：点一下扣住按下、抬起时补发；手机屏外原样放行")
    func directMatchesOldDispatch() {
        var pipeline = TouchPipeline(shapers: [DirectShaper()])
        let press = pipeline.handle(event(.leftDown, 100, 300, 0), from: 0, regions: [phone])
        #expect(press == TouchStep(passOriginal: false, effects: [.hold]))
        let release = pipeline.handle(event(.leftUp, 100, 300, 0.1), from: 0, regions: [phone])
        #expect(release == TouchStep(passOriginal: false, effects: [.command(.replayPress, region: phone), .command(.replayCurrent, region: phone), .dropHeld]))

        #expect(pipeline.handle(event(.leftDown, 2000, 300, 1), from: 0, regions: [phone]) == TouchStep(passOriginal: true, effects: []))
        #expect(pipeline.handle(event(.leftUp, 2000, 300, 1.1), from: 0, regions: [phone]) == TouchStep(passOriginal: true, effects: [.dropHeld]))
    }

    @Test("点一下：抬起那一步把原事件交给了 App（补发），按下那一步还扣着；点在关闭按钮上、按住松手当右键时抬起被吞掉，不算交出")
    func deliversCurrent() {
        var region = phone
        region.closeButton = CloseButton(frame: CGRect(x: 8, y: 30, width: 14, height: 14), window: 7,
                                         windowFrame: CGRect(x: 0, y: 22, width: 540, height: 900))
        var pipeline = TouchPipeline(shapers: [DirectShaper()])
        #expect(!pipeline.handle(event(.leftDown, 100, 300, 0), from: 0, regions: [region]).deliversCurrent)
        #expect(pipeline.handle(event(.leftUp, 100, 300, 0.1), from: 0, regions: [region]).deliversCurrent)
        // 手机屏外：原样放行
        #expect(pipeline.handle(event(.leftDown, 2000, 300, 1), from: 0, regions: [region]).deliversCurrent)
        #expect(pipeline.handle(event(.leftUp, 2000, 300, 1.1), from: 0, regions: [region]).deliversCurrent)
        // 关闭按钮
        _ = pipeline.handle(event(.leftDown, 15, 37, 2), from: 0, regions: [region])
        let close = pipeline.handle(event(.leftUp, 15, 37, 2.1), from: 0, regions: [region])
        #expect(close.effects.contains(.command(.closeWindow(at: CGPoint(x: 15, y: 37)), region: region)))
        #expect(!close.deliversCurrent)
        // 按住 0.6 秒松手：右键
        _ = pipeline.handle(event(.leftDown, 100, 300, 3), from: 0, regions: [region])
        let hold = pipeline.handle(event(.leftUp, 100, 300, 3.6), from: 0, regions: [region])
        #expect(hold.effects.contains(.command(.rightClick(at: CGPoint(x: 100, y: 300)), region: region)))
        #expect(!hold.deliversCurrent)
    }

    @Test("拼出来的按下不扣原事件（没有能补发的按下）；不按键的移动在手机屏里吞掉，滑开就是滚动")
    func stitchedPressIsNotHeld() {
        var pipeline = TouchPipeline(shapers: [StitchingShaper()])
        #expect(pipeline.handle(event(.move, 100, 300, 0), from: 0, regions: [phone]) == TouchStep(passOriginal: false, effects: []))
        let drag = pipeline.handle(event(.move, 100, 360, 0.02), from: 0, regions: [phone])
        #expect(!drag.passOriginal)
        #expect(scrollPhases(drag) == [.began, .changed])
    }

    @Test("一个原事件整理出几个输入时按顺序分派：先收掉上一笔（作废扣着的），再扣住这次按下；放不放行只看代表这个原事件的输入")
    func multipleInputsInOrder() {
        var pipeline = TouchPipeline(shapers: [StitchingShaper()])
        _ = pipeline.handle(event(.move, 100, 300, 0), from: 0, regions: [phone])
        let press = pipeline.handle(event(.leftDown, 100, 300, 0.01), from: 0, regions: [phone])
        #expect(press == TouchStep(passOriginal: false, effects: [.dropHeld, .hold]))
        let release = pipeline.handle(event(.leftUp, 100, 300, 0.02), from: 0, regions: [phone])
        #expect(release.effects == [.command(.replayPress, region: phone), .command(.replayCurrent, region: phone), .dropHeld])
    }

    @Test("到点收尾：没到时间不动；到了就收掉那一笔，滚动发 ended；之后不用再等")
    func expireFinishesStroke() {
        var pipeline = TouchPipeline(shapers: [DirectShaper(), StitchingShaper()])
        #expect(pipeline.deadline == nil)
        _ = pipeline.handle(event(.move, 100, 300, 0), from: 1, regions: [phone])
        _ = pipeline.handle(event(.move, 100, 360, 0.25), from: 1, regions: [phone])
        #expect(pipeline.deadline == 0.375)
        #expect(pipeline.expire(now: 0.3, regions: [phone]).effects.isEmpty)
        let finished = pipeline.expire(now: 0.4, regions: [phone])
        #expect(scrollPhases(finished) == [.ended])
        #expect(finished.effects.last == .dropHeld)
        #expect(pipeline.deadline == nil)
    }

    @Test("接管的事件种类是各家的并集；事件交给发它的那一家整理")
    func kindsAndRouting() {
        var pipeline = TouchPipeline(shapers: [DirectShaper(), StitchingShaper()])
        #expect(pipeline.kinds == [.leftDown, .leftDrag, .leftUp, .move])
        #expect(TouchPipeline(shapers: [DirectShaper()]).kinds == [.leftDown, .leftDrag, .leftUp])
        // 直通的那一家不整理移动：不产生输入，原样放行
        #expect(pipeline.handle(event(.move, 100, 300, 0), from: 0, regions: [phone]) == TouchStep(passOriginal: true, effects: []))
        #expect(pipeline.deadline == nil)
        _ = pipeline.handle(event(.move, 100, 300, 0), from: 1, regions: [phone])
        #expect(pipeline.deadline != nil)
    }
}

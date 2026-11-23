// CrossDesk 的手势整理。它的 iPhone 客户端（绝对位置模式）把手指操作发成这样（源码 apps/ios/CrossDeskMobile/Input/RemoteTouchInputView.swift，
// Mac 端把带左键的移动发成拖动、不带键的发成移动：apps/desktop/src/platform/macos/input/mouse/mouse_controller.cpp）：
//   点一下      → 移动、左键按下、左键抬起，几乎同时到（手指抬起时才发）
//   单指滑动    → 只有不按键的移动，没有按下、抬起（它的滑动只是挪指针）
//   按住 0.35 秒 → 这时才发移动、左键按下；之后手指的移动是拖动，松手发抬起
// 整理成翻译器认的形态：
// - 不按键的移动拼成一笔（只能是滚动），停手 strokeTimeout 没有新的移动就当松手。每一下都先压着，等下一个事件来了再交：
//   紧跟着按下的那一下是点按、长按的前导（在点的地方），不是滑动。不压的话它会停掉惯性、让后面的按下补发点击，
//   滑完马上点时还会让滚动一下跳到点的地方
// - 相邻两下隔得比 maxStep 远时看轨迹：和上一步大致同向、长度跟得上（快甩一下一百多点、中途丢了几下）是同一笔；
//   掉头、一下跳出老远的是两个手势（点按前导、甩完又甩一下：手指回到下面重新甩）。不看到达的时间间隔：
//   网络卡一下，前一甩的尾巴和后一甩的开头挤在同一毫秒里到。上一步太短（方向不可信）、还没有上一步（只压着一下）时才按时间分：
//   紧挨着到的是快甩的头两下。卡得比收尾时间还久时，前一甩已经收了尾，剩下的那一下尾巴落在它终点附近，下一下又跳得远就不连过去
// - 到点收尾时，压着的那下属于已经开始的那一笔就交出去（短甩只有两三下，少一下就不滚了），孤零零的一下扔掉
// - 按下的时刻往前推 holdDelay，还原手指真正落下的时刻：翻译器按 iPhone 的习惯判点击、长按右键、长按选择照旧成立
// 不按键的移动都原样放行（指针跟着手指走，和 CrossDesk 本来一样），整理出的输入都不代表它。
// 两个时长取自源码、没有真机标定：真机上判错了先看这里
import Foundation
import SnugCore

package struct CrossDeskShaper: TouchShaper {
    /// 它的长按手势要按住这么久才发按下（UILongPressGestureRecognizer.minimumPressDuration）
    package static let holdDelay: TimeInterval = 0.35
    /// 不按键的移动停了这么久没再来，就当手指已经离开：它不发抬起，只能等。
    /// 太短会把慢慢滑的一笔断成几笔，太长甩完要多等这么久才开始惯性
    package static let strokeTimeout: TimeInterval = 0.12
    /// 隔得比这远（Snug 屏的点）的下一下要看轨迹才知道是不是同一笔：快甩时一下能有一百多点（60Hz、宽档放大）
    package static let maxStep: CGFloat = 100
    /// 只压着一下、还没有方向时，远处的下一下隔了这么久才到是另一个手势（抬手、再落下）；同一笔里相邻两下是 8–17 毫秒（60–120Hz）
    package static let splitGap: TimeInterval = 0.05
    /// 远的这一步和上一步的夹角余弦至少这么多（60 度以内）才算同一笔
    static let minTurnCosine: CGFloat = 0.5
    /// 远的这一步最多是上一步的几倍（再加 maxStep）：甩的时候一下比一下快，丢三下就是四倍
    static let maxStepGrowth: CGFloat = 4
    /// 上一步比这短（点）就看不出方向（开头那一下、停住时原地的两下），远的下一步按时间分
    static let minDirectionStep: CGFloat = 12
    /// 前一甩收尾后这么久之内、落在它终点附近的孤零零一下，是卡住后才到的尾巴
    static let stragglerWindow: TimeInterval = 0.5

    package let kinds: Set<PointerEvent.Kind> = [.leftDown, .leftDrag, .leftUp, .move]
    /// 压着还没交的那一下不按键的移动
    private var held: (point: CGPoint, time: TimeInterval)?
    /// 这一笔已经交出去的最后一下；nil = 还没开始（只压着一下）
    private var stroke: (point: CGPoint, time: TimeInterval)?
    /// 上一笔收尾时的最后一下：认卡住后才到的尾巴
    private var lastEnded: (point: CGPoint, time: TimeInterval)?
    /// 左键按着（按下之后、抬起之前）：这时的移动是拖动
    private var leftHeld = false

    package init() {}

    package var deadline: TimeInterval? { held.map { $0.time + Self.strokeTimeout } }

    package mutating func shape(_ event: PointerEvent) -> [ShapedInput] {
        switch event.kind {
        case .move where leftHeld, .leftDrag:
            return [current(.drag, event)]
        case .move:
            var out: [ShapedInput] = []
            if let last = held, !continues(last, with: event) {
                // 另一个手势。压着的那下接着已经开始的那一笔（它到的时候判过），算它的；孤零零的一下扔掉
                out = (stroke == nil ? [] : flushHeld()) + finishStroke()
                held = nil
            }
            out += flushHeld()
            held = (event.location, event.time)
            return out
        case .leftDown:
            leftHeld = true
            // 压着的那一下是这次按下的前导，扔掉
            held = nil
            var press = current(.press, event)
            press.input.time -= Self.holdDelay
            return finishStroke() + [press]
        case .leftUp:
            leftHeld = false
            return [current(.release, event)]
        }
    }

    /// 压着的那下接着已经开始的那一笔就交出去再收尾；孤零零的一下（还没开始的）扔掉。
    /// 按下晚到的点按前导隔得远，到的时候已经判成另一个手势、成了孤零零的一下，在这里扔掉，滚动不会跳过去
    package mutating func expire(now: TimeInterval) -> [ShapedInput] {
        guard let deadline, now >= deadline else { return [] }
        let flushed = stroke == nil ? [] : flushHeld()
        held = nil
        return flushed + finishStroke()
    }

    /// 下一下接着上一下（last，压着的）：离得不远；远的话，有看得出方向的上一步（这一笔交出去的最后一下到 last）就看轨迹跟不跟得上，
    /// 没有就看是不是紧挨着到。last 是卡住后才到的前一甩的尾巴时不连
    private func continues(_ last: (point: CGPoint, time: TimeInterval), with event: PointerEvent) -> Bool {
        let step = CGVector(dx: event.location.x - last.point.x, dy: event.location.y - last.point.y)
        let length = hypot(step.dx, step.dy)
        guard length > Self.maxStep else { return true }
        guard let previous = stroke?.point else {
            if let ended = lastEnded, last.time - ended.time <= Self.stragglerWindow,
               hypot(last.point.x - ended.point.x, last.point.y - ended.point.y) <= Self.maxStep { return false }
            return event.time - last.time < Self.splitGap
        }
        let before = CGVector(dx: last.point.x - previous.x, dy: last.point.y - previous.y)
        let beforeLength = hypot(before.dx, before.dy)
        guard beforeLength >= Self.minDirectionStep else { return event.time - last.time < Self.splitGap }
        guard length <= Self.maxStepGrowth * beforeLength + Self.maxStep else { return false }
        return (step.dx * before.dx + step.dy * before.dy) / (length * beforeLength) >= Self.minTurnCosine
    }

    /// 交出压着的那一下：一笔的第一下当按下，之后当拖动
    private mutating func flushHeld() -> [ShapedInput] {
        guard let move = held else { return [] }
        held = nil
        let kind: TouchInput.Kind = stroke == nil ? .press : .drag
        stroke = move
        return [ShapedInput(TouchInput(kind, at: move.point, time: move.time, synthetic: true), fromCurrent: false)]
    }

    /// 给已经开始的那一笔补一个抬起，记在交出去的最后一下的时刻：翻译器按松手前的速度算惯性
    private mutating func finishStroke() -> [ShapedInput] {
        guard let last = stroke else { return [] }
        stroke = nil
        lastEnded = last
        return [ShapedInput(TouchInput(.release, at: last.point, time: last.time, synthetic: true), fromCurrent: false)]
    }

    private func current(_ kind: TouchInput.Kind, _ event: PointerEvent) -> ShapedInput {
        ShapedInput(TouchInput(kind, at: event.location, time: event.time), fromCurrent: true)
    }
}

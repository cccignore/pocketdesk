// CrossDesk 的手势整理。它的 iPhone 客户端（绝对位置模式）把手指操作发成这样（源码 apps/ios/CrossDeskMobile/Input/RemoteTouchInputView.swift，
// Mac 端把带左键的移动发成拖动、不带键的发成移动：apps/desktop/src/platform/macos/input/mouse/mouse_controller.cpp）：
//   点一下      → 移动、左键按下、左键抬起，几乎同时到（手指抬起时才发）
//   单指滑动    → 只有不按键的移动，没有按下、抬起（它的滑动只是挪指针）
//   按住 0.35 秒 → 这时才发移动、左键按下；之后手指的移动是拖动，松手发抬起
// 整理成翻译器认的形态：不按键的移动拼成一笔（只能是滚动），停手 strokeTimeout 没有新的移动就当松手；
// 按下的时刻往前推 holdDelay，还原手指真正落下的时刻，翻译器按 iPhone 的习惯判点击、长按右键、长按选择照旧成立。
// 两个时长取自源码、没有真机标定：真机上判错了先看这里
import Foundation
import SnugCore

package struct CrossDeskShaper: TouchShaper {
    /// 它的长按手势要按住这么久才发按下（UILongPressGestureRecognizer.minimumPressDuration）
    package static let holdDelay: TimeInterval = 0.35
    /// 不按键的移动停了这么久没再来，就当手指已经离开：它不发抬起，只能等。
    /// 太短会把慢慢滑的一笔断成几笔，太长甩完要多等这么久才开始惯性
    package static let strokeTimeout: TimeInterval = 0.12

    package let kinds: Set<PointerEvent.Kind> = [.leftDown, .leftDrag, .leftUp, .move]
    /// 正在拼的那一笔最后一下在哪、什么时候
    private var stroke: (point: CGPoint, time: TimeInterval)?
    /// 左键按着（按下之后、抬起之前）：这时的移动是拖动
    private var leftHeld = false

    package init() {}

    package var deadline: TimeInterval? { stroke.map { $0.time + Self.strokeTimeout } }

    package mutating func shape(_ event: PointerEvent) -> [ShapedInput] {
        switch event.kind {
        case .move where leftHeld, .leftDrag:
            return [current(.drag, event)]
        case .move:
            let kind: TouchInput.Kind = stroke == nil ? .press : .drag
            stroke = (event.location, event.time)
            return [ShapedInput(TouchInput(kind, at: event.location, time: event.time, synthetic: true), fromCurrent: true)]
        case .leftDown:
            leftHeld = true
            var press = current(.press, event)
            press.input.time -= Self.holdDelay
            return finishStroke() + [press]
        case .leftUp:
            leftHeld = false
            return [current(.release, event)]
        }
    }

    package mutating func expire(now: TimeInterval) -> [ShapedInput] {
        guard let deadline, now >= deadline else { return [] }
        return finishStroke()
    }

    /// 给没收尾的那一笔补一个抬起，记在最后一下的时刻：翻译器按松手前的速度算惯性
    private mutating func finishStroke() -> [ShapedInput] {
        guard let last = stroke else { return [] }
        stroke = nil
        return [ShapedInput(TouchInput(.release, at: last.point, time: last.time, synthetic: true), fromCurrent: false)]
    }

    private func current(_ kind: TouchInput.Kind, _ event: PointerEvent) -> ShapedInput {
        ShapedInput(TouchInput(kind, at: event.location, time: event.time), fromCurrent: true)
    }
}

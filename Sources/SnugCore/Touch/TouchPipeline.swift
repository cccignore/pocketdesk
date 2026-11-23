// 手势分派：远控注入的事件 → 发它的那一家整理成标准输入 → 共用的翻译器 → 要做的事（扣住原事件、补发、滚动）。
// 系统那半（截事件、补发、定时器）在 SnugSystem 的 TouchTap，这里是纯逻辑，可以测。
// 一个原事件可能整理出几个输入（先收掉上一笔、再按下），要做的事按顺序排好，系统那半照着做
import CoreGraphics
import Foundation

/// 系统那半要做的一件事
public enum TouchEffect: Equatable, Sendable {
    /// 把手上这个原事件扣下，留着补发（TouchCommand.replayPress 补的就是它）
    case hold
    /// region：这一笔按在哪块范围里（点关闭按钮时要核对按钮）
    case command(TouchCommand, region: TouchRegion?)
    /// 一笔结束：扣着的按下作废
    case dropHeld
}

public struct TouchStep: Equatable, Sendable {
    public var passOriginal: Bool
    public var effects: [TouchEffect]

    public init(passOriginal: Bool, effects: [TouchEffect]) {
        self.passOriginal = passOriginal
        self.effects = effects
    }
}

public struct TouchPipeline: Sendable {
    private var shapers: [any TouchShaper]
    private var translator = TouchTranslator()
    /// 这一笔按在哪块范围里：之后的拖动、抬起跟着这一下走，手指滑出范围也一样
    private var pressed: TouchRegion?

    /// shapers：每家一个，下标就是 handle 的 source
    public init(shapers: [any TouchShaper]) {
        self.shapers = shapers
    }

    /// 要接管的事件种类：各家的并集
    public var kinds: Set<PointerEvent.Kind> { shapers.reduce(into: []) { $0.formUnion($1.kinds) } }

    /// 最早要收尾的时间
    public var deadline: TimeInterval? { shapers.compactMap(\.deadline).min() }

    /// 惯性还在走：调用方按 Momentum.frameRate 定时调 momentumFrame()
    public var isCoasting: Bool { translator.isCoasting }

    public mutating func momentumFrame() -> ScrollStep? { translator.momentumFrame() }

    /// source：发这个事件的是第几家；regions：此刻要翻译手势的范围
    public mutating func handle(_ event: PointerEvent, from source: Int, regions: [TouchRegion]) -> TouchStep {
        dispatch(shapers[source].shape(event), regions: regions)
    }

    /// 到点了：交给到点的那几家收尾
    public mutating func expire(now: TimeInterval, regions: [TouchRegion]) -> TouchStep {
        var inputs: [ShapedInput] = []
        for i in shapers.indices where (shapers[i].deadline ?? .infinity) <= now {
            inputs += shapers[i].expire(now: now)
        }
        return dispatch(inputs, regions: regions)
    }

    /// 原事件放不放行只看代表它的输入（一个都没有就放行：不是手势的原料）；补出来的输入只产生要做的事
    private mutating func dispatch(_ inputs: [ShapedInput], regions: [TouchRegion]) -> TouchStep {
        var pass = true
        var effects: [TouchEffect] = []
        for shaped in inputs {
            let input = shaped.input
            if input.kind == .press { pressed = regions.first { $0.frame.contains(input.location) } }
            let region = pressed
            let response = translator.handle(input, in: region)
            if shaped.fromCurrent { pass = pass && response.passOriginal }
            // 拼出来的按下没有原事件可扣（远控根本没发按下）
            if input.kind == .press, !response.passOriginal, shaped.fromCurrent, !input.synthetic { effects.append(.hold) }
            effects += response.commands.map { .command($0, region: region) }
            if input.kind == .release { effects.append(.dropHeld) }
        }
        return TouchStep(passOriginal: pass, effects: effects)
    }
}

// 手势整理：每家远控把手指操作发成什么样的鼠标事件各不相同，整理器把它整理成翻译器认的标准输入（按下 → 拖动 → 抬起）。
// 每家一份，各家的整理器放在自己的目标里（Sources/Remotes），这里只有端口和「原样直通」这一种（UU 实测就是标准输入）。
// 纯状态机，时间由调用方给；不发抬起的远控要超时收尾，由调用方到 deadline 时调 expire
import CoreGraphics
import Foundation

/// 远控注入的一个指针事件（中性写法）：整理的原料
public struct PointerEvent: Equatable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case leftDown, leftDrag, leftUp
        /// 不按键的移动
        case move
    }

    public var kind: Kind
    public var location: CGPoint
    /// 单调时间（秒）
    public var time: TimeInterval

    public init(_ kind: Kind, at location: CGPoint, time: TimeInterval) {
        self.kind = kind
        self.location = location
        self.time = time
    }
}

/// 整理出来的一个标准输入。fromCurrent：它代表手上这个原事件（原事件放不放行、补发时补的都是它）；
/// false 是整理器顺带补出来的，比如新的一按来了，先给没收尾的上一笔补一个抬起
public struct ShapedInput: Equatable, Sendable {
    public var input: TouchInput
    public var fromCurrent: Bool

    public init(_ input: TouchInput, fromCurrent: Bool) {
        self.input = input
        self.fromCurrent = fromCurrent
    }
}

public protocol TouchShaper: Sendable {
    /// 这家要接管的事件种类：事件监听只收各家的并集
    var kinds: Set<PointerEvent.Kind> { get }
    mutating func shape(_ event: PointerEvent) -> [ShapedInput]
    /// 下一次要调 expire 的时间；nil = 没有要等的
    var deadline: TimeInterval? { get }
    /// 到点了：远控不发抬起的那一笔在这里收尾
    mutating func expire(now: TimeInterval) -> [ShapedInput]
}

/// 原样直通：远控把手指的按下、拖动、抬起都当成左键发来（UU 实测），一个事件就是一个标准输入
public struct DirectShaper: TouchShaper {
    public let kinds: Set<PointerEvent.Kind> = [.leftDown, .leftDrag, .leftUp]
    public let deadline: TimeInterval? = nil

    public init() {}

    public mutating func shape(_ event: PointerEvent) -> [ShapedInput] {
        let kind: TouchInput.Kind
        switch event.kind {
        case .leftDown: kind = .press
        case .leftDrag: kind = .drag
        case .leftUp: kind = .release
        case .move: return []
        }
        return [ShapedInput(TouchInput(kind, at: event.location, time: event.time), fromCurrent: true)]
    }

    public mutating func expire(now: TimeInterval) -> [ShapedInput] { [] }
}

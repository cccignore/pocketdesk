// 手势翻译和 CGEvent 之间的读写：接管哪几种事件、事件类型对应 TouchInput 的哪一种、拼要补发的事件、打上记号发出去；
// InjectedEvents 认哪些事件是远控注入的。监听线程、状态机和按 TouchCommand 分派在 TouchTap。
// 补发的事件打上记号：拷贝出来的事件保留远控的进程号，不打记号会被自己再接管一次，来回打转
import CoreGraphics
import Darwin
import Foundation
import SnugCore

enum TouchEvents {
    /// eventSourceUserData 里的记号（'SNUG'）
    private static let marker: Int64 = 0x534E_5547

    /// 接管的事件：各家整理器要的并集（只登记 UU 时只有鼠标左键的按下、拖动、抬起）
    static func mask(_ kinds: Set<PointerEvent.Kind>) -> CGEventMask {
        kinds.map(type(of:)).reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    }

    static func kind(of type: CGEventType) -> PointerEvent.Kind? {
        switch type {
        case .leftMouseDown: .leftDown
        case .leftMouseDragged: .leftDrag
        case .leftMouseUp: .leftUp
        case .mouseMoved: .move
        default: nil
        }
    }

    private static func type(of kind: PointerEvent.Kind) -> CGEventType {
        switch kind {
        case .leftDown: .leftMouseDown
        case .leftDrag: .leftMouseDragged
        case .leftUp: .leftMouseUp
        case .move: .mouseMoved
        }
    }

    /// Snug 自己补发的事件
    static func isReplay(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    /// 打上记号再发：监听再看到它时原样放行
    static func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cgSessionEventTap)
    }

    /// 右键按下、抬起
    static func rightClick(at point: CGPoint) -> [CGEvent] {
        [CGEventType.rightMouseDown, .rightMouseUp].compactMap { type in
            let click = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)
            click?.setIntegerValueField(.mouseEventClickState, value: 1)
            return click
        }
    }

    /// 带相位的像素滚动：App 看到的和触控板两指滑动一样
    static func scroll(_ s: ScrollStep) -> CGEvent? {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: s.pixelsY, wheel2: s.pixelsX, wheel3: 0) else { return nil }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: s.phase.rawValue)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: s.momentum.rawValue)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: s.deltaY)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: s.deltaX)
        e.location = s.location
        return e
    }
}

/// 认远控注入的事件：取事件的来源（进程的可执行文件路径、事件自带的记号），交给各家的 InjectedEventSource 判断。
/// 路径按进程号缓存（事件多，一个进程只查一次）；只按记号认的远控不查路径。本机的触控板、鼠标不是它们发的，一律不认
struct InjectedEvents {
    let injectors: [InjectedEventSource]
    private let needsPath: Bool
    private var paths: [pid_t: String] = [:]

    init(injectors: [InjectedEventSource]) {
        self.injectors = injectors
        needsPath = injectors.contains(where: \.needsExecutablePath)
    }

    /// 是第几家注入的；nil = 不是远控注入的
    mutating func source(of event: CGEvent) -> Int? {
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid > 0 else { return nil }
        let origin = EventOrigin(executablePath: needsPath ? path(of: pid) : "",
                                 userData: event.getIntegerValueField(.eventSourceUserData))
        return injectors.firstIndex { $0.matches(origin) }
    }

    private mutating func path(of pid: pid_t) -> String {
        if let path = paths[pid] { return path }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        let path = length > 0 ? String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        paths[pid] = path
        return path
    }
}

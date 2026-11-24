// 手机上打的字：远控注入的按键。键盘让位跟着它走（AppController.followTyping）：打字说明手机键盘开着。
// 只认按键是不是这家远控发的（和手势翻译认指针事件同一套，InjectedEvents），不读按了什么、打了什么字。
// 用全局监听（被动收副本，不经过它就送到 App，不拖慢打字）；只在远程期间、远控声明了键盘会盖住画面时开
import AppKit
import SnugCore

@MainActor
public final class InjectedTyping {
    /// 手机上打了字：在主线程上调，最多每 interval 一次（连着打字时不必每个键都去读焦点）
    public var onType: (() -> Void)?
    private var monitor: Any?
    private var watching: InjectedEventSource?
    private var injected = InjectedEvents(injectors: [])
    private var lastReported: TimeInterval = -.infinity
    /// 这一轮（watch 到停）里认出过手机上打的字：头一回记一笔日志，排查「打字不让位」先看有没有这一行
    private var seen = false
    static let interval: TimeInterval = 0.5

    public init() {}

    /// 认这一家注入的按键；nil 停掉。和上次一样就什么都不做（每拍都会调）
    public func watch(_ injector: InjectedEventSource?) {
        guard injector != watching else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        watching = injector
        guard let injector else { return Log.info("不再看手机上打的字") }
        injected = InjectedEvents(injectors: [injector])
        seen = false
        // 按键的全局监听要辅助功能权限，手势翻译本来就要它；没给时系统返回 nil
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if monitor == nil {
            Log.warn("看不了手机上打的字（建按键监听失败，多半是没有辅助功能权限）：先开键盘再打字时不会自动让出键盘")
        } else {
            Log.info("开始看手机上打的字（只认 \(injector) 发来的按键，不读内容）：打字时键盘让位跟着走")
        }
    }

    private func handle(_ event: NSEvent) {
        guard let cg = event.cgEvent, injected.source(of: cg) != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReported >= Self.interval else { return }
        lastReported = now
        if !seen {
            seen = true
            Log.info("认出了手机上打的字（\(watching.map { "\($0)" } ?? "") 注入的按键）")
        }
        onType?()
    }
}

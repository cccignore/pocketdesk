// 只在启动时读一次显示器的远控（CrossDesk）看不到 Snug 的屏时，没人远程就自动重启它：不然用户要等连上手机才发现没有手机屏。
// 远程中绝不重启：CrossDesk 默认「连接断开后锁屏」，退出时还有控制端连着，它收尾时先断开所有会话再锁屏
// （gui_application.cpp 的 Cleanup → BeginShutdown → HandleScreenLock）。会话层说不在远程还不够，远控还要报确知没人连着
// （RemoteObservation.absent），读不到电源断言时不算没人。
// 防循环：同一批屏只自动重启一次（Snug 每次建屏编号都会变，新编号就是新的一批），两次自动重启至少隔 cooldown；
// 没成或重启后还是看不到，留给菜单栏的「重启」手动点。每拍调一次，日志只在结论或这一批屏变了时记一行
import Foundation

public struct AutoRestart: Sendable {
    /// 看不到屏要持续这么久才重启：几块屏陆续建好、远控的日志还在后台读时，结论会变
    public static let settle: TimeInterval = 5
    /// 两次自动重启至少隔这么久：屏反复重建时不至于一直重启它
    public static let cooldown: TimeInterval = 60

    public enum Decision: Equatable, Sendable {
        /// 看得到屏
        case clear
        /// 看不到屏还不到 settle
        case settling
        /// 现在重启（只交一次，之后是 restarting，直到 finished）
        case restart
        case restarting
        /// 远程中（含断开后等重连）：等远程结束
        case inSession
        /// 读不到它有没有控制端连着：不算没人
        case presenceUnknown
        /// 离上次自动重启不到 cooldown
        case coolingDown
        /// 这批屏已经自动重启过一次：不再自动重启，留给菜单栏
        case gaveUp
    }

    public struct Step: Equatable, Sendable {
        public var decision: Decision
        /// 结论或这一批屏变了才有：写进日志的一行（gaveUp 记成警告）
        public var logLine: String?

        public init(decision: Decision, logLine: String?) {
            self.decision = decision
            self.logLine = logLine
        }
    }

    /// 界面上的名字：日志里写「重启 CrossDesk」，和菜单栏那一项对得上
    public let remote: String
    /// 这一次看不到的是哪一批屏、从什么时候开始（这一批变了重新算）
    private var batch: (screens: Set<DisplayID>, since: Date)?
    /// 上一次自动重启的是哪一批、什么时候
    private var last: (screens: Set<DisplayID>, at: Date)?
    public private(set) var isRestarting = false
    /// 上一拍记过日志的结论和那一批屏：没变就不再记
    private var logged: (decision: Decision, screens: Set<DisplayID>)?

    public init(remote: String) {
        self.remote = remote
    }

    /// stale：它看不到 Snug 的屏时，交此刻在线的 Snug 屏（认这一批用）；看得到交 nil。
    /// inSession：会话层是否在远程中（含断开后等重连）。absent：它报了确知没人连着
    public mutating func update(stale: Set<DisplayID>?, inSession: Bool, absent: Bool, now: Date) -> Step {
        let screens = stale ?? []
        let decision = decide(screens, inSession: inSession, absent: absent, now: now)
        let changed = logged.map { $0.decision != decision || $0.screens != screens } ?? true
        logged = (decision, screens)
        return Step(decision: decision, logLine: changed ? line(decision, screens, now: now) : nil)
    }

    /// 重启跑完了：reopened 是退出后又打开、还在运行。没成时交回要记的一行（警告），这批屏不再自动重启
    public mutating func finished(reopened: Bool) -> String? {
        isRestarting = false
        guard !reopened else { return nil }
        let screens = last.map { Self.names($0.screens) } ?? ""
        return "自动重启 \(remote)：没成（原因见上一行），屏 \(screens) 不再自动重启；它还在运行时菜单栏有「重启 \(remote)」，没在运行就要手动打开它"
    }

    private mutating func decide(_ screens: Set<DisplayID>, inSession: Bool, absent: Bool, now: Date) -> Decision {
        if isRestarting { return .restarting }
        guard !screens.isEmpty else {
            batch = nil
            return .clear
        }
        if batch?.screens != screens { batch = (screens, now) }
        if last?.screens == screens { return .gaveUp }
        if inSession { return .inSession }
        if !absent { return .presenceUnknown }
        if let last, now.timeIntervalSince(last.at) < Self.cooldown { return .coolingDown }
        guard let batch, now.timeIntervalSince(batch.since) >= Self.settle else { return .settling }
        last = (screens, now)
        isRestarting = true
        return .restart
    }

    private func line(_ decision: Decision, _ screens: Set<DisplayID>, now: Date) -> String? {
        let names = Self.names(screens)
        let prefix = "自动重启 \(remote)："
        switch decision {
        case .clear, .restarting:
            return nil
        case .settling:
            return prefix + "它看不到屏 \(names)，等 \(Int(Self.settle)) 秒屏稳定下来，没人远程就重启它"
        case .restart:
            let waited = batch.map { now.timeIntervalSince($0.since) } ?? 0
            return prefix + String(format: "看不到屏 %@ 已 %.1f 秒，没人远程、它也报了没有控制端连着：现在重启（这批屏只自动重启这一次）", names, waited)
        case .inSession:
            return prefix + "先不重启：远程进行中（它看不到屏 \(names)），这时退出它会断掉远程、可能锁屏。等远程结束再重启"
        case .presenceUnknown:
            return prefix + "先不重启：读不到它有没有控制端连着（它看不到屏 \(names)），连着时退出它会锁屏。菜单栏有「重启 \(remote)」"
        case .coolingDown:
            let elapsed = last.map { now.timeIntervalSince($0.at) } ?? 0
            return prefix + "先不重启：上次自动重启才过 \(Int(elapsed)) 秒，隔满 \(Int(Self.cooldown)) 秒再重启（它看不到屏 \(names)）"
        case .gaveUp:
            return prefix + "屏 \(names) 已经自动重启过一次，它还是看不到：不再自动重启，菜单栏留着「重启 \(remote)」"
        }
    }

    private static func names(_ screens: Set<DisplayID>) -> String {
        screens.sorted().map { "#\($0)" }.joined(separator: "、")
    }
}

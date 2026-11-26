// 只在启动时读一次显示器的远控（CrossDesk）看不到 Snug 的屏时，没人远程就自动重启它：不然用户要等连上手机才发现没有手机屏。
// 远程中绝不重启：CrossDesk 默认「连接断开后锁屏」，退出时还有控制端连着，它收尾时先断开所有会话再锁屏
// （gui_application.cpp 的 Cleanup → BeginShutdown → HandleScreenLock）。会话层说不在远程还不够：控制端连上后它要等分辨率、
// 开始抓屏才持有电源断言（最多约 2 秒，抓屏起不来时一直不持有），这段时间会话层看不到。所以动手前还要适配器现场确认没人连着、
// 也没人正在连（RemoteAdapter.restartBlocker），重启的那一下退出前再确认一次。
// 防循环：同一批屏只重启一次（Snug 每次建屏编号都会变，新编号就是新的一批；手动点的也算），两次重启至少隔 cooldown；
// 没成或重启后还是看不到，留给菜单栏的「重启」手动点。每拍调一次，日志只在结论或这一批屏变了时记一行
import Foundation

public struct AutoRestart: Sendable {
    /// 看不到屏要持续这么久才重启：几块屏陆续建好、远控的日志还在后台读时，结论会变
    public static let settle: TimeInterval = 5
    /// 两次重启至少隔这么久：屏反复重建时不至于一直重启它
    public static let cooldown: TimeInterval = 60
    /// 记得最近重启过的几批屏：在线的屏在几批之间来回跳时，每一批也只重启一次
    private static let triedLimit = 8

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
        /// 现场确认不了没人连着（读不到、刚有人在连）：等确认了
        case unconfirmed
        /// 离上次重启不到 cooldown
        case coolingDown
        /// 这批屏已经重启过一次：不再自动重启，留给菜单栏
        case gaveUp
    }

    /// 一次重启怎么收场
    public enum Outcome: Equatable, Sendable {
        /// 退出后又打开了，过一会儿还在运行
        case reopened
        /// 退出前一查不行（刚开始远程、刚有人在连、手动重启正在跑、它已经没在运行），根本没动它：不算重启过
        case blocked
        /// 退不掉、打不开、打开后又退出了
        case failed
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

    /// 界面上的名字：日志里写「重启 <它>」，和菜单栏那一项对得上
    public let remote: String
    /// 这一次看不到的是哪一批屏、从什么时候开始（这一批变了重新算）
    private var batch: (screens: Set<DisplayID>, since: Date)?
    /// 重启过（自动或手动）的几批屏，最近的在后
    private var tried: [Set<DisplayID>] = []
    private var lastRestartAt: Date?
    /// 这次自动重启之前的上次重启时刻：退出前一查不行（blocked）时撤回这次，冷却照旧从上次算
    private var previousRestartAt: Date?
    public private(set) var isRestarting = false
    /// 上一拍记过日志的结论和那一批屏：没变就不再记
    private var logged: (decision: Decision, screens: Set<DisplayID>)?

    public init(remote: String) {
        self.remote = remote
    }

    /// stale：它看不到 Snug 的屏时，交此刻在线的 Snug 屏（认这一批用）；看得到交 nil。
    /// inSession：会话层是否在远程中（含断开后等重连）。blocker：现场确认有没有人连着、正在连，没有交 nil、有交原因；
    /// 只在快要重启时才问（要读一次系统状态）
    public mutating func update(stale: Set<DisplayID>?, inSession: Bool, blocker: () -> String?, now: Date) -> Step {
        let screens = stale ?? []
        var reason: String?
        let decision = decide(screens, inSession: inSession, now: now) {
            reason = blocker()
            return reason
        }
        let changed = logged.map { $0.decision != decision || $0.screens != screens } ?? true
        logged = (decision, screens)
        return Step(decision: decision, logLine: changed ? line(decision, screens, reason: reason, now: now) : nil)
    }

    /// 重启跑完了。没成时交回要记的一行（警告），这批屏不再自动重启；blocked 撤回这次，确认了再重启
    public mutating func finished(_ outcome: Outcome) -> String? {
        isRestarting = false
        switch outcome {
        case .reopened:
            return nil
        case .blocked:
            if !tried.isEmpty { tried.removeLast() }
            lastRestartAt = previousRestartAt
            return nil
        case .failed:
            let screens = tried.last.map(Self.names) ?? ""
            return "自动重启 \(remote)：没成（原因见上一行），屏 \(screens) 不再自动重启；它还在运行时菜单栏有「重启 \(remote)」，没在运行就要手动打开它"
        }
    }

    /// 用户点了菜单栏的「重启」、真的退出了它：这批屏算重启过，冷却从这一刻算
    public mutating func noteManualRestart(now: Date) {
        if let screens = batch?.screens { remember(screens) }
        lastRestartAt = now
    }

    private mutating func decide(_ screens: Set<DisplayID>, inSession: Bool, now: Date, blocker: () -> String?) -> Decision {
        if isRestarting { return .restarting }
        guard !screens.isEmpty else {
            batch = nil
            return .clear
        }
        if batch?.screens != screens { batch = (screens, now) }
        if tried.contains(screens) { return .gaveUp }
        if inSession { return .inSession }
        if let lastRestartAt, now.timeIntervalSince(lastRestartAt) < Self.cooldown { return .coolingDown }
        guard let batch, now.timeIntervalSince(batch.since) >= Self.settle else { return .settling }
        if blocker() != nil { return .unconfirmed }
        remember(screens)
        previousRestartAt = lastRestartAt
        lastRestartAt = now
        isRestarting = true
        return .restart
    }

    private mutating func remember(_ screens: Set<DisplayID>) {
        tried.removeAll { $0 == screens }
        tried.append(screens)
        if tried.count > Self.triedLimit { tried.removeFirst() }
    }

    private func line(_ decision: Decision, _ screens: Set<DisplayID>, reason: String?, now: Date) -> String? {
        let names = Self.names(screens)
        let prefix = "自动重启 \(remote)："
        switch decision {
        case .clear, .restarting:
            return nil
        case .settling:
            return prefix + "它看不到屏 \(names)，等 \(Int(Self.settle)) 秒屏稳定下来，没人远程就重启它"
        case .restart:
            let waited = batch.map { now.timeIntervalSince($0.since) } ?? 0
            return prefix + String(format: "看不到屏 %@ 已 %.1f 秒，没人远程，现场确认了没人连着、也没人正在连：现在重启（这批屏只重启这一次）",
                                   names, waited)
        case .inSession:
            return prefix + "先不重启：远程进行中（它看不到屏 \(names)），这时退出它会断掉远程、可能锁屏。等远程结束再重启"
        case .unconfirmed:
            return prefix + "先不重启：确认不了没人连着（\(reason ?? "原因不明")），这时退出它可能锁屏。等确认了再重启（它看不到屏 \(names)）"
        case .coolingDown:
            let elapsed = lastRestartAt.map { now.timeIntervalSince($0) } ?? 0
            return prefix + "先不重启：上次重启才过 \(Int(elapsed)) 秒，隔满 \(Int(Self.cooldown)) 秒再重启（它看不到屏 \(names)）"
        case .gaveUp:
            return prefix + "屏 \(names) 已经重启过一次，它还是看不到：不再自动重启，菜单栏留着「重启 \(remote)」"
        }
    }

    private static func names(_ screens: Set<DisplayID>) -> String {
        screens.sorted().map { "#\($0)" }.joined(separator: "、")
    }
}

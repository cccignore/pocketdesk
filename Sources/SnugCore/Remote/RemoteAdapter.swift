// 远控适配层的端口：核心只认这几样，不认识具体是哪家远控。每家远控一个适配器（Sources/Remotes），在 App 层登记（Snug/App/Remotes.swift）。
// 适配器每拍交一份中性的观测；连接判定、会话、建屏、手势翻译都在核心，各家共用
import Foundation

/// 一家远控的身份
public struct RemoteIdentity: Equatable, Sendable {
    /// 写进日志和命令行参数的名字（「检测到 UU 连入」）。日志措辞靠它保持不变，自检也按它认
    public let logName: String
    /// 界面上的名字（「在 UU远程 中选择 Snug 的屏」）
    public let displayName: String
    /// 这家远控自己的 App：不出现在 App 资源库里（把遥控器放到 Snug 的屏上没有意义，退了它远程就断了）
    public let bundleIDs: Set<String>
    /// 被远程时注入鼠标事件的进程：手势翻译只接管它发来的
    public let injector: InjectedEventSource
    /// 只在启动时读一次显示器列表、之后加的屏看不到：装着它时 Snug 的屏常驻（见 ScreenPlan），它要在屏建好之后启动
    public let readsDisplaysOnce: Bool
    /// 它在手机上压住画面的部分：手机屏按它让位（见 ScreenFit）
    public let clientInsets: ClientInsets
    /// 它把手机上打好的字当「按键 + 文字」注入：Mac 用中文输入法时会被再组一次字，远程期间换成英文输入法（见 InputSourceSwap）
    public let needsASCIIInputSource: Bool

    public init(logName: String, displayName: String, bundleIDs: Set<String>, injector: InjectedEventSource, readsDisplaysOnce: Bool = false,
                clientInsets: ClientInsets = .standard, needsASCIIInputSource: Bool = false) {
        self.logName = logName
        self.displayName = displayName
        self.bundleIDs = bundleIDs
        self.injector = injector
        self.readsDisplaysOnce = readsDisplaysOnce
        self.clientInsets = clientInsets
        self.needsASCIIInputSource = needsASCIIInputSource
    }
}

/// 一个鼠标事件从哪来：来源进程的可执行文件路径（读不到时为空串），和事件自带的 eventSourceUserData（没写时为 0）
public struct EventOrigin: Equatable, Sendable {
    public var executablePath: String
    public var userData: Int64

    public init(executablePath: String, userData: Int64 = 0) {
        self.executablePath = executablePath
        self.userData = userData
    }
}

/// 认哪些事件是这家远控注入的，本机的触控板、鼠标不是它发的。两种认法：
/// - 按进程：注入事件的是一个单独的可执行文件（UU 的 UURemoteServer）
/// - 按记号：远控给每个注入事件写同一个 eventSourceUserData（CrossDesk），界面和后台是同一个程序也分得清，不用查进程
public struct InjectedEventSource: Equatable, Sendable, CustomStringConvertible {
    private enum Rule: Equatable, Sendable {
        case process(executableName: String)
        case marker(Int64)
    }

    private let rule: Rule

    public init(executableName: String) {
        rule = .process(executableName: executableName)
    }

    public init(marker: Int64) {
        rule = .marker(marker)
    }

    /// 判之前要不要先查来源进程的路径：按进程号查路径是一次系统调用，只按记号认的省掉
    public var needsExecutablePath: Bool {
        if case .process = rule { return true }
        return false
    }

    public func matches(_ origin: EventOrigin) -> Bool {
        switch rule {
        case .process(let name): (origin.executablePath as NSString).lastPathComponent == name
        case .marker(let marker): origin.userData == marker
        }
    }

    /// 写进日志的写法：开启手势翻译时列出接管谁发来的，「手势没反应」先看这一行
    public var description: String {
        switch rule {
        case .process(let name): name
        case .marker(let marker): String(format: "记号 0x%llX", marker)
        }
    }
}

/// 一拍里对一家远控的观测
public struct RemoteObservation: Equatable, Sendable {
    /// 有人在远程的正面证据。读不到、没认出都不算缺席：适配器只在确有证据时报在场
    public var present: Bool
    /// 认出的控制端，按适配器给的顺序。空 = 没认出，不代表没人
    public var controllers: [String]
    /// 此刻在推的屏。nil = 不知道，不代表没在推（AppState.watching 把 nil 当作「在看」）
    public var streamedDisplay: DisplayID?
    /// 写进连入、断开日志的信号快照：排查误判时才知道是哪一路信号在变
    public var evidence: String

    public init(present: Bool, controllers: [String], streamedDisplay: DisplayID?, evidence: String) {
        self.present = present
        self.controllers = controllers
        self.streamedDisplay = streamedDisplay
        self.evidence = evidence
    }
}

/// 一家远控这一拍的观测，带上是哪家
public struct RemoteReading: Equatable, Sendable {
    public let remote: RemoteIdentity
    public let observation: RemoteObservation

    public init(remote: RemoteIdentity, observation: RemoteObservation) {
        self.remote = remote
        self.observation = observation
    }
}

/// 一家远控的适配器：盯着这家远控在本机留下的痕迹（进程、日志、界面），每拍交一份观测
@MainActor
public protocol RemoteAdapter: AnyObject {
    /// 身份是这家远控的，不是某个实例的：登记处、诊断命令、运行中的适配器都从这里取，只有一份
    static var identity: RemoteIdentity { get }
    init()
    /// App 开始监控时调一次
    func start()
    /// 退出收尾前调一次
    func stop()
    /// 每拍调一次。wallClock 是墙钟（系统日志的时间戳是墙钟）；会话层另用单调时钟
    func sample(wallClock: Date) -> RemoteObservation
    /// 这家的手势整理（见 TouchShaper）：每次开启手势翻译各建一份，在监听线程上用。默认原样直通
    nonisolated static func makeTouchShaper() -> any TouchShaper
}

extension RemoteAdapter {
    public var identity: RemoteIdentity { Self.identity }

    public nonisolated static func makeTouchShaper() -> any TouchShaper { DirectShaper() }

    /// 手势翻译用的：认哪些事件是它注入的，怎么整理。整理器是值类型，每次开启手势翻译拿一份新拷贝
    public static var touchSource: TouchSource {
        let fresh = makeTouchShaper()
        return TouchSource(injector: identity.injector) { fresh }
    }
}

/// 手势翻译接管的一家远控
public struct TouchSource: Sendable {
    public let injector: InjectedEventSource
    public let makeShaper: @Sendable () -> any TouchShaper

    public init(injector: InjectedEventSource, makeShaper: @escaping @Sendable () -> any TouchShaper) {
        self.injector = injector
        self.makeShaper = makeShaper
    }
}

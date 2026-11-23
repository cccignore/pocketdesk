// AppController：把远控的观测、会话层和屏幕调度接在一起。
// 每 0.5 秒一拍：适配器给出观测 → 会话层判断连没连、是不是同一次远程 → ScreenPlan 按配置算出要哪些屏，交给 DeskSet。
// 要翻译手势的屏在时开手势翻译，范围跟着那几块屏走。全仓唯一写配置的地方；界面只读 state，意图见 AppController+Intents
import AppKit
import SnugCore
import SnugSystem

/// 显式标 Sendable（主线程隔离的类本来就是）：意图协议要求 Sendable，而遵循写在另一个文件里，
/// 不在这里标的话编译器会警告「Sendable 须在类所在的文件里声明」
@MainActor
final class AppController: Sendable {
    static let tickInterval: TimeInterval = 0.5
    /// 每隔这么久核对一次各块屏上的窗口还在不在
    static let verifyInterval: TimeInterval = 2

    let state = AppState()
    let updater: Updater
    let desks: DeskSet
    /// App 资源库的统一数据源（手机、平板屏和电脑屏的资源库共用）。界面碰得到的系统入口只有 desks 和它
    let catalog: AppCatalog
    /// 手机、平板屏上的截图（小横条的相机键）
    let screenshots = Screenshots(system: ScreenshotService())
    /// 用户从菜单或设置里点「退出」（由 AppDelegate 接到退出流程上）
    var onQuitRequested: (() -> Void)?

    let store: ConfigStore
    /// --preview-screens：不等远程就建出开着的屏
    private let preview: Bool
    /// 登记的远控适配器，按登记顺序（两家同时报在场时归第一家）
    let remotes = Remotes.all.map { $0.adapter.init() }
    private var session = RemoteSession()
    private let touch: TouchTap
    private var watcher: DisplayWatcher?
    private var tickTimer: Timer?
    private var lastTickAt: Date?
    private var lastVerifyAt = Date.distantPast
    /// 手势翻译此刻覆盖哪几块屏：变了才记日志
    private var gestureScreens: Set<ScreenID> = []
    /// 常驻：装着只在启动时读一次显示器的远控时，开着的屏不等远程（见 ScreenPlan）
    private var resident = false
    /// 装着的远控（日志名）：手势只接管这几家
    private var installedRemotes: [String]?
    /// 远程期间换成的英文输入法，远程结束换回（只对注入文字会被中文输入法再组一次字的远控）
    private var inputSwap = InputSourceSwap()
    /// Snug 的屏每个编号这一次上线的时刻（墙钟，和远控进程的启动时刻比）：只在启动时读一次显示器的远控比它早启动就看不到这块屏。
    /// Snug 每次建屏编号都会变（真机实测 #13 → #14），新编号就是新上线
    private var snugDisplaysOnlineSince: [DisplayID: Date] = [:]
    /// 某一拍真看到它不在了：从哪一刻（单调钟）开始不在的。掉线不到 snugDisplayBlip 又回来的不算重新上线
    /// （屏幕配置一变会短暂重排）；休眠时不走拍、看不到它不在，醒来照旧不算
    private var snugDisplaysGoneAt: [DisplayID: TimeInterval] = [:]
    private static let snugDisplayBlip: TimeInterval = 2
    /// 单调时钟的起点：系统改时间不会让「已经过了多久」算错
    private let anchor = (date: Date(), uptime: ProcessInfo.processInfo.systemUptime)

    init(paths: SnugPaths, preview: Bool = false) {
        self.preview = preview
        store = ConfigStore(url: paths.config)
        let devices = Self.loadDevices()
        let helper = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let windows = WindowService()
        let apps = AppService()
        desks = DeskSet(displays: VirtualDisplayService(helper: helper), windows: windows, apps: apps,
                        arrangement: DisplayArrangementService(), paths: paths, defaultZoom: store.config.zoomSteps)
        catalog = AppCatalog(apps: apps, windows: windows, excluding: Set(remotes.flatMap(\.identity.bundleIDs)))
        touch = TouchTap(sources: Self.installed(remotes).map { type(of: $0).touchSource })
        state.config = store.config
        state.previewing = preview
        state.devices = devices
        state.accessibilityTrusted = AX.isTrusted
        updater = Updater(state: state)
        AX.configureTimeout()
        // 选过的型号按机型库现在的数值来（机型库改过数值时跟着改），建屏前就定下来
        for screen in store.config.screens {
            let resolved = devices.resolve(screen.device)
            guard resolved != screen.device else { continue }
            changeConfig("「\(screen.name)」的型号 \(resolved.title) 按机型库更新") { config in
                if let i = config.screens.firstIndex(where: { $0.id == screen.id }) { config.screens[i].device = resolved }
            }
        }
        // 2.6.x 设的主屏只在远程时生效；改为常驻后，代价要在设置里看过确认框才算数。升上来先撤掉，同样在建屏前定下来
        if let current = Updater.current, let last = store.config.lastVersion {
            changeConfig("从 \(last) 升级：原先只在远程时生效的设为主屏改回「不改」（现为常驻，需在设置中重新选定）") {
                _ = $0.dropRemoteOnlyMain(running: current)
            }
        }
    }

    var now: Date { anchor.date.addingTimeInterval(ProcessInfo.processInfo.systemUptime - anchor.uptime) }

    /// 机型库随 App 发（Contents/Resources）。读不出来只是没有型号可选，还能自己填分辨率，屏照常按配置里的比例
    private static func loadDevices() -> DeviceCatalog {
        guard let url = Bundle.main.url(forResource: "device-models", withExtension: "json") else {
            Log.error("App 里没有机型库 device-models.json（打包漏了），型号只能自己填")
            return .empty
        }
        do {
            let devices = try DeviceCatalog(contentsOf: url)
            let counts = DeviceKind.allCases.map { kind in "\(kind.rawValue) \(devices.brands(in: [kind]).flatMap(\.models).count)" }
            Log.info("机型库：\(devices.brands.count) 段品牌、\(devices.models.count) 款机型（\(counts.joined(separator: "、"))）")
            return devices
        } catch {
            Log.error("机型库读不出来（\(url.path)）：\(error)；型号只能自己填")
            return .empty
        }
    }

    /// 开始监控。有权限的话先把上次没放回去的窗口放回去
    func start() {
        desks.onChange = { [weak self] desks in self?.desksChanged(desks) }
        desks.onGone = { [weak self] gone in self?.catalog.forget(gone) }
        touch.onCloseWindow = { [weak self] window in self?.desks.closePlaced(window: window) }
        screenshots.onChange = { [weak self] overlay in self?.screenshotChanged(overlay) }
        desks.onTopologyChange = { [weak self] in
            guard let self else { return }
            session.noteSelfInducedChange(at: now)
        }
        let watcher = DisplayWatcher { [weak self] in
            self?.desks.displaysChanged()
            self?.syncGestures()
        }
        watcher.start()
        self.watcher = watcher
        remotes.forEach { $0.start() }
        if state.accessibilityTrusted { desks.recover() }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // 加进 .common：菜单展开、窗口拖动期间也照常走
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        refreshInstalled()
        tick()
        let enabled = store.config.screens.filter(\.enabled).map(\.name)
        Log.info("开始监控（开着的屏：\(enabled.isEmpty ? "没有" : enabled.joined(separator: "、"))，手势\(store.config.gestures ? "已开" : "已关")"
                 + "\(preview ? "，预览模式：不等远程直接建屏" : "")）")
    }

    /// 停止监控（退出收尾前调用）
    func stopMonitoring() {
        restoreInputSource(because: "退出 Snug")
        tickTimer?.invalidate()
        tickTimer = nil
        watcher?.stop()
        remotes.forEach { $0.stop() }
    }

    // MARK: 每拍

    private func tick() {
        let now = now
        if let last = lastTickAt, now.timeIntervalSince(last) > 1.5 {
            Log.warn(String(format: "主线程卡了 %.1fs", now.timeIntervalSince(last)))
        }
        lastTickAt = now
        refreshTrust()
        screenshots.expire()
        let wallClock = Date()
        let readings = remotes.map { RemoteReading(remote: $0.identity, observation: $0.sample(wallClock: wallClock)) }
        handle(session.update(readings, now: now))
        keepPointerOffSnugScreens()
        refreshStaleRemotes(at: wallClock, readings: readings)
        if now.timeIntervalSince(lastVerifyAt) >= Self.verifyInterval {
            lastVerifyAt = now
            desks.verifyPlacement()
            desks.checkReturns()
            desks.settleDisplays()
            refreshScreenRecording()
            refreshInstalled()
        }
        // 推流只有一路画面（UU 一次只让一台设备控制，V12），在推哪块屏看这次远程的归属方
        state.update(\.streamedDisplay, session.tracked?.observation.streamedDisplay)
    }

    /// 会话变化统一在这里落地（每拍和菜单的「立即结束」共用）
    private func handle(_ transitions: [SessionTransition]) {
        if transitions.contains(.ended) {
            // 远程结束先说一声一块屏都不要，再按「不在远程」重算（只剩常驻的主屏）。不先说「不要」的话，下一次在同一拍里
            // 开始时前后要的屏一样，上一次在手机上退出的屏会带进这一次。同一拍里先「不要」再「要」不会撤屏重建（DeskSet 排队时读的是最新结论）
            desks.setWishes([])
        }
        applyPlan()
        desks.setRemote(session.inEpisode)
        swapInputSource(transitions)
        state.update(\.connection, session.isConnected ? .connected : (session.inEpisode ? .reconnecting : .idle))
        state.update(\.controllers, session.controllers)
        state.update(\.remoteName, session.owner?.displayName)
    }

    /// 远程开始（这一家注入的文字会被中文输入法再组一次字）时换成英文输入法，远程结束换回
    private func swapInputSource(_ transitions: [SessionTransition]) {
        if transitions.contains(where: { if case .began = $0 { true } else { false } }), session.owner?.needsASCIIInputSource == true,
           let current = InputSources.current(),
           let ascii = inputSwap.begin(current: current.id, currentIsASCII: current.isASCII, ascii: InputSources.asciiCapable()) {
            let switched = InputSources.select(ascii)
            Log.info("远程开始：输入法 \(current.id) → \(ascii)\(switched ? "" : "（没换成）")（\(session.owner?.displayName ?? "") 注入的文字会被中文输入法再组一次字，中文在手机上打）")
        }
        if transitions.contains(.ended) { restoreInputSource(because: "远程结束") }
    }

    private func restoreInputSource(because reason: String) {
        guard let current = InputSources.current(), let original = inputSwap.end(current: current.id) else { return }
        let switched = InputSources.select(original)
        Log.info("\(reason)：输入法换回 \(original)\(switched ? "" : "（没换成）")")
    }

    /// 断开后远控不再动指针，而 Snug 的屏要等重连窗口才撤。这十几秒里指针若停在 Snug 的屏上，
    /// 那块屏在本机看不见，就成了「鼠标找不回来」。等待期每拍看一眼：用户一动又可能滑回去；
    /// 只在断开与重连之间生效，连上马上停（issue #29）。常驻的屏没人远程时一直在、本机同样看不见，一直看着。
    /// 设为主屏的那块除外：它常驻、远程结束也不撤，指针留在上面正是设主屏的本意（重连后接着用），和撤屏时指针落到主屏一致
    private func keepPointerOffSnugScreens() {
        guard !session.isConnected, session.inEpisode || resident else { return }
        for (id, desk) in state.desks.desks where id != store.config.mainScreen {
            guard let display = desk.display else { continue }
            Cursor.leave(display)
        }
    }

    /// 不等重连窗口，立即结束本次远程（菜单栏「立即结束本次远程」，issue #29）。
    /// 只在重连等待期里有意义：不在这段时间里时 session.endNow() 什么都不做
    func endSessionNow() {
        guard let change = session.endNow() else { return }
        handle([change])
    }

    /// 按此刻的配置和会话算出要哪些屏，交给 DeskSet（结论没变就什么都不做）
    func applyPlan() {
        desks.setWishes(ScreenPlan.wishes(config: store.config, remote: session.inEpisode, trusted: state.accessibilityTrusted,
                                          preview: preview, resident: resident, insets: state.clientInsets))
    }

    /// 只在启动时读一次显示器的远控，按启动时登记的几块分位置切显示器，Snug 的屏没有位置可占就切不过去。开机时两个都自动打开，
    /// 谁先谁后说不准：每拍看一眼，列进 staleRemotes，菜单栏给「重启」。远控报了登记了哪些（RemoteObservation.registeredDisplays）时
    /// 按 RegisteredDisplays 判：Snug 重启后屏换了编号，占原来那块的位置照样切得到，不用重启。没报时按启动时刻比：远控的进程比
    /// 此刻在线的哪块屏这一次上线早就算看不到（屏上线和下一拍之间启动的会误报一次，重启无害）
    private func refreshStaleRemotes(at now: Date, readings: [RemoteReading]) {
        let online = Set(state.desks.desks.values.compactMap(\.display))
        let uptime = ProcessInfo.processInfo.systemUptime
        for display in snugDisplaysOnlineSince.keys where !online.contains(display) && snugDisplaysGoneAt[display] == nil {
            snugDisplaysGoneAt[display] = uptime
        }
        for display in online {
            if snugDisplaysOnlineSince[display] == nil {
                snugDisplaysOnlineSince[display] = now
            } else if let gone = snugDisplaysGoneAt.removeValue(forKey: display), uptime - gone > Self.snugDisplayBlip {
                snugDisplaysOnlineSince[display] = now
            }
        }
        let since = online.compactMap { snugDisplaysOnlineSince[$0] }.max()
        let all = Screens.online()
        let stale = remotes.map(\.identity).filter { identity in
            guard identity.readsDisplaysOnce, let since else { return false }
            if let registered = readings.first(where: { $0.remote == identity })?.observation.registeredDisplays, let all {
                return RegisteredDisplays.misses(registered, snug: online, online: all)
            }
            let apps = identity.bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            return apps.contains { ($0.launchDate ?? .distantFuture) < since }
        }.map(\.displayName)
        guard stale != state.staleRemotes else { return }
        Log.info(stale.isEmpty ? "只在启动时读一次显示器的远控都看得到 Snug 的屏了"
                               : "\(stale.joined(separator: "、")) 比 Snug 的屏先启动，看不到这些屏：要重启它（菜单栏有「重启」）")
        state.staleRemotes = stale
    }

    /// 装着哪几家远控：手势只接管装着的（没装的远控要的事件不收，比如 CrossDesk 的不按键的移动，只装 UU 时监听和以前一样）；
    /// 装着只在启动时读一次显示器的就常驻。装上、卸掉随时会变，和核对窗口同一拍重看（查一次约 0.05 毫秒）
    private func refreshInstalled() {
        let installed = Self.installed(remotes)
        let names = installed.map(\.identity.logName)
        if names != installedRemotes {
            let changed = installedRemotes != nil
            installedRemotes = names
            if changed {
                touch.setSources(installed.map { type(of: $0).touchSource })
                syncGestures()
            }
            Log.info("装着的远控：\(names.isEmpty ? "没有" : names.joined(separator: "、"))（手势只接管这几家）")
        }
        // 让位：装着的几家说法一致就用它的；一家没装、或者几家各说各的（同时装着 UU 和 CrossDesk），按 UU 实测的默认
        let claimed = Set(installed.map(\.identity.clientInsets))
        let insets = claimed.count == 1 ? claimed.first ?? .standard : .standard
        if insets != state.clientInsets {
            state.clientInsets = insets
            Log.info("手机屏让位改为竖屏上下共 \(Int(insets.portraitVertical))、横屏左右共 \(Int(insets.landscapeHorizontal))、横屏上下共 \(Int(insets.landscapeVertical)) 点"
                     + (claimed.count > 1 ? "（装着的远控让位不一致，按默认）" : ""))
            applyPlan()
        }
        let needing = installed.map(\.identity).filter(\.readsDisplaysOnce)
        guard needing.isEmpty == resident else { return }
        resident = !needing.isEmpty
        let shown = needing.map(\.displayName).joined(separator: "、")
        Log.info(resident ? "装着 \(shown)（只在启动时读一次显示器）：开着的屏常驻，不等远程；它要在屏建好之后启动才看得到"
                          : "没有只在启动时读一次显示器的远控了：屏改回远程时才建")
        applyPlan()
    }

    /// 自家 App 装在本机的远控
    private static func installed(_ remotes: [any RemoteAdapter]) -> [any RemoteAdapter] {
        remotes.filter { $0.identity.bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } }
    }

    /// 权限是用户在系统设置里给的，随时会变：刚给上时把上次没放回去的窗口放回去
    private func refreshTrust() {
        let trusted = AX.isTrusted
        guard trusted != state.accessibilityTrusted else { return }
        state.accessibilityTrusted = trusted
        Log.info("辅助功能权限：\(trusted ? "已授权" : "被收回")")
        if trusted { desks.recover() }
    }

    /// 录屏权限也是用户在系统设置里给的：开着截图键时每两秒对一次（不跟着每拍去读 TCC），变了记一笔
    func refreshScreenRecording() {
        guard store.config.screenshot else { return }
        let trusted = screenshots.trusted
        guard trusted != state.screenRecordingTrusted else { return }
        state.screenRecordingTrusted = trusted
        Log.info("录屏权限：\(trusted ? "已授权" : "未授权")")
    }

    // MARK: 屏

    private func desksChanged(_ desks: DeskSet.State) {
        state.desks = desks
        // 截图所在的屏没了：浮着的截图、裁剪中的、正给它截的一并收掉，不然下次连上还盖着旧截图
        screenshots.dismiss(outside: Set(desks.desks.compactMap { $0.value.display == nil ? nil : $0.key }))
        syncGestures()
    }

    private func screenshotChanged(_ overlay: ScreenshotOverlay?) {
        state.screenshotOverlay = overlay
        state.screenshotScreen = screenshots.screen
        syncGestures()
    }

    /// 手势翻译只在要翻译手势的屏在、开着手势时运行；正在裁剪截图的那块屏除外（拖动是在画选区，不能翻译成滚动）。
    /// 每块屏一块范围，跟着那块屏走（换档、屏幕重排时 DisplayWatcher 也会调到这里）
    func syncGestures() {
        let cropping = state.screenshotOverlay?.isCropping == true ? state.screenshotScreen : nil
        let covered: [(id: ScreenID, region: TouchRegion)] = store.config.gestures ? state.desks.desks.compactMap { id, desk in
            guard id != cropping, desk.behavior.touch, let display = desk.display else { return nil }
            // 窗口露着时才拦它的关闭按钮：列表盖着时那个位置是列表
            return (id, TouchRegion(screen: CGDisplayBounds(display), closeButton: desk.listVisible ? nil : desk.closeButton))
        } : []
        let ids = Set(covered.map(\.id))
        if ids != gestureScreens {
            gestureScreens = ids
            let names = ids.map(screenName).sorted().joined(separator: "、")
            let why = !store.config.gestures ? "（总开关关着）" : cropping.map { "（\(screenName($0)) 在裁剪截图）" } ?? ""
            Log.info("手势翻译范围：\(ids.isEmpty ? "没有屏" : names)\(why)")
        }
        state.update(\.gesturesFailed, !touch.setRegions(covered.map(\.region)))
    }

    private func screenName(_ id: ScreenID) -> String {
        store.config.screens.first { $0.id == id }?.name ?? id.rawValue
    }
}

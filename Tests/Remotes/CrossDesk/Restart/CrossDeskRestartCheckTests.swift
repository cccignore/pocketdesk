import Foundation
import RemoteCrossDesk
import Testing

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func ago(_ seconds: Double) -> Date { now.addingTimeInterval(-seconds) }

@Suite("退出 CrossDesk 前现场确认没人连着 CrossDeskRestartCheck")
struct CrossDeskRestartCheckTests {
    @Test("常量：日志静了 10 秒才算没人正在连")
    func constants() {
        #expect(CrossDeskRestartCheck.quietLogs == 10)
    }

    @Test("没持有电源断言、两份日志都静了 10 秒以上：可以退出它")
    func vacant() {
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(10)), ("minirtc.log", ago(600))], now: now) { false } == nil)
    }

    @Test("持有电源断言（有控制端连着、在抓屏）、读不到断言：不退出")
    func sharingOrUnknown() throws {
        let logs: [(String, Date?)] = [("crossdesk.log", ago(600)), ("minirtc.log", ago(600))]
        #expect(try #require(CrossDeskRestartCheck.blocker(sharing: true, logs: logs, now: now) { false }).contains("连着"))
        #expect(try #require(CrossDeskRestartCheck.blocker(sharing: nil, logs: logs, now: now) { false }).contains("读不到电源断言"))
    }

    @Test("控制端刚连上、还没开始抓屏时没有断言，但它的日志正在写（握手、等分辨率、抓屏重试）：不退出")
    func connectingBeforeCapture() throws {
        // 真机 11-26 15:35：minirtc.log 48.613「Remote user joined transmission」，49.998 才持有断言
        let reason = CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(600)), ("minirtc.log", ago(1.4))], now: now) { false }
        #expect(try #require(reason).contains("minirtc.log"))
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(9.9)), ("minirtc.log", ago(600))], now: now) { false } != nil)
    }

    @Test("读不到日志的写入时刻（文件没了、没权限）、时刻在未来（改过系统时间）：确认不了，不退出")
    func unreadableLogs() throws {
        let missing = CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(600)), ("minirtc.log", nil)], now: now) { false }
        #expect(try #require(missing).contains("minirtc.log"))
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", now.addingTimeInterval(30))], now: now) { false } != nil)
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [], now: now) { false } != nil)
    }

    @Test("日志里最近连上的控制端还没断开（没开始抓屏、没断言，日志也静了，比如它没有屏幕录制权限）、看不全这次启动以来的日志：不退出")
    func connectedPerLog() throws {
        let quiet: [(String, Date?)] = [("crossdesk.log", ago(600)), ("minirtc.log", ago(600))]
        #expect(try #require(CrossDeskRestartCheck.blocker(sharing: false, logs: quiet, now: now) { true }).contains("还没断开"))
        #expect(try #require(CrossDeskRestartCheck.blocker(sharing: false, logs: quiet, now: now) { nil }).contains("看不全"))
    }

    @Test("便宜的先查：持有断言、日志还在写时不去读日志内容")
    func lazyContentRead() {
        var reads = 0
        _ = CrossDeskRestartCheck.blocker(sharing: true, logs: [("crossdesk.log", ago(600))], now: now) { reads += 1; return false }
        _ = CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(1))], now: now) { reads += 1; return false }
        #expect(reads == 0)
        _ = CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(600))], now: now) { reads += 1; return false }
        #expect(reads == 1)
    }
}

@Suite("从 CrossDesk 的日志看有没有控制端连着")
struct CrossDeskConnectedLogTests {
    private func records(_ text: String) -> [CrossDeskLogRecord] {
        text.split(separator: "\n").compactMap { CrossDeskLogRecord(line: String($0)) }
    }

    /// 真机 v1.7.7 11-26 的几行：15:29:59 启动，15:35:49 有控制端连上（发主机信息时列出本机显示器），15:36:25 最后一个断开
    private let session = """
    [2026-11-26 15:29:59.840] [crossdesk] [info] Logger initialized
    [2026-11-26 15:35:49.758] [crossdesk] [info] [peer_event_handler.cpp:665] Local display [1:Built-in Retina Display]
    [2026-11-26 15:35:49.758] [crossdesk] [info] [peer_event_handler.cpp:665] Local display [2:Snug 手机屏]
    [2026-11-26 15:35:49.998] [crossdesk] [info] [session_device_manager.cpp:346] Start screen capturer, show cursor: false
    [2026-11-26 15:35:50.888] [crossdesk] [info] [peer_event_handler.cpp:665] Local display [1:Built-in Retina Display]
    [2026-11-26 15:36:25.732] [crossdesk] [info] [connection_runtime.cpp:246] Last remote controller disconnected; recovering privacy, reason=connection_closed
    """

    @Test("认出发主机信息那一行（控制端连上时写，比开始抓屏早）")
    func hostAnnounced() {
        #expect(records(session)[1].event == .hostAnnounced)
        #expect(records(session)[5].event == .lastControllerLeft)
    }

    @Test("最后一次连上之后有「最后一个控制端断开」、这次启动以来没人连过：没人连着")
    func vacant() throws {
        let all = records(session)
        let launch = all[0].date
        #expect(CrossDeskLogRecord.controllerConnected(since: launch, in: all, logStart: launch) == false)
        #expect(CrossDeskLogRecord.controllerConnected(since: launch, in: [all[0]], logStart: launch) == false)
    }

    @Test("连上之后还没写「最后一个控制端断开」：有人连着；断开后又连上也算")
    func connected() {
        let all = records(session)
        let launch = all[0].date
        #expect(CrossDeskLogRecord.controllerConnected(since: launch, in: Array(all.prefix(5)), logStart: launch) == true)
        let again = all + records("[2026-11-26 15:40:00.000] [crossdesk] [info] [peer_event_handler.cpp:665] Local display [1:Built-in Retina Display]")
        #expect(CrossDeskLogRecord.controllerConnected(since: launch, in: again, logStart: launch) == true)
    }

    @Test("上一个进程留下的行不算；日志没从这次启动记起（滚动掉了）、读不到日志：看不出来")
    func scope() {
        let all = records(session)
        let relaunch = all[5].date.addingTimeInterval(60)
        #expect(CrossDeskLogRecord.controllerConnected(since: relaunch, in: Array(all.prefix(5)), logStart: all[0].date) == false)
        #expect(CrossDeskLogRecord.controllerConnected(since: all[0].date, in: all, logStart: all[0].date.addingTimeInterval(5)) == nil)
        #expect(CrossDeskLogRecord.controllerConnected(since: all[0].date, in: [], logStart: nil) == nil)
    }
}

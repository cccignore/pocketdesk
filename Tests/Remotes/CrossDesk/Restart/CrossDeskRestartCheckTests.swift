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
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(10)), ("minirtc.log", ago(600))], now: now) == nil)
    }

    @Test("持有电源断言（有控制端连着、在抓屏）、读不到断言：不退出")
    func sharingOrUnknown() throws {
        let logs: [(String, Date?)] = [("crossdesk.log", ago(600)), ("minirtc.log", ago(600))]
        #expect(try #require(CrossDeskRestartCheck.blocker(sharing: true, logs: logs, now: now)).contains("连着"))
        #expect(try #require(CrossDeskRestartCheck.blocker(sharing: nil, logs: logs, now: now)).contains("读不到电源断言"))
    }

    @Test("控制端刚连上、还没开始抓屏时没有断言，但它的日志正在写（握手、等分辨率、抓屏重试）：不退出")
    func connectingBeforeCapture() throws {
        // 真机 11-26 15:35：minirtc.log 48.613「Remote user joined transmission」，49.998 才持有断言
        let reason = CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(600)), ("minirtc.log", ago(1.4))], now: now)
        #expect(try #require(reason).contains("minirtc.log"))
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(9.9)), ("minirtc.log", ago(600))], now: now) != nil)
    }

    @Test("读不到日志的写入时刻（文件没了、没权限）、时刻在未来（改过系统时间）：确认不了，不退出")
    func unreadableLogs() throws {
        let missing = CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", ago(600)), ("minirtc.log", nil)], now: now)
        #expect(try #require(missing).contains("minirtc.log"))
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [("crossdesk.log", now.addingTimeInterval(30))], now: now) != nil)
        #expect(CrossDeskRestartCheck.blocker(sharing: false, logs: [], now: now) != nil)
    }
}

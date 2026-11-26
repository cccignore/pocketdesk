import Foundation
import RemoteCrossDesk
import Testing

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func ago(_ seconds: Double) -> Date { now.addingTimeInterval(-seconds) }
private let quiet: [(String, Date?)] = [("crossdesk.log", ago(600)), ("minirtc.log", ago(600))]

@Suite("退出 CrossDesk 前现场确认 CrossDeskRestartCheck")
struct CrossDeskRestartCheckTests {
    @Test("常量：日志静了 10 秒才算没人正在连")
    func constants() {
        #expect(CrossDeskRestartCheck.quietLogs == 10)
    }

    @Test("关着「连接断开后锁屏」、没持有电源断言、两份日志都静了 10 秒以上：可以退出它")
    func vacant() {
        #expect(CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: false,
                                              logs: [("crossdesk.log", ago(10)), ("minirtc.log", ago(600))], now: now) == nil)
    }

    @Test("开着「连接断开后锁屏」（它的默认）、读不到它的设置：一律不退出，有没有人连着没法完全确认，连着时退出它会锁屏")
    func locksOnDisconnect() throws {
        let on = try #require(CrossDeskRestartCheck.blocker(lockOnDisconnect: true, sharing: false, logs: quiet, now: now))
        #expect(on.contains("连接断开后锁屏"))
        let unknown = try #require(CrossDeskRestartCheck.blocker(lockOnDisconnect: nil, sharing: false, logs: quiet, now: now))
        #expect(unknown.contains("config.ini"))
    }

    @Test("持有电源断言（有控制端连着、在抓屏）、读不到断言：不退出，免得断掉远程")
    func sharingOrUnknown() throws {
        #expect(try #require(CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: true, logs: quiet, now: now)).contains("连着"))
        #expect(try #require(CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: nil, logs: quiet, now: now)).contains("读不到电源断言"))
    }

    @Test("控制端刚连上、还没开始抓屏时没有断言，但它的日志正在写（握手、等分辨率）：不退出")
    func connectingBeforeCapture() throws {
        // 真机 11-26 15:35：minirtc.log 48.613「Remote user joined transmission」，49.998 才持有断言
        let reason = CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: false,
                                                   logs: [("crossdesk.log", ago(600)), ("minirtc.log", ago(1.4))], now: now)
        #expect(try #require(reason).contains("minirtc.log"))
        #expect(CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: false,
                                              logs: [("crossdesk.log", ago(9.9)), ("minirtc.log", ago(600))], now: now) != nil)
    }

    @Test("读不到日志的写入时刻（文件没了、没权限）、时刻在未来（改过系统时间）、没有日志：确认不了，不退出")
    func unreadableLogs() throws {
        let missing = CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: false,
                                                    logs: [("crossdesk.log", ago(600)), ("minirtc.log", nil)], now: now)
        #expect(try #require(missing).contains("minirtc.log"))
        #expect(CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: false, logs: [("crossdesk.log", now.addingTimeInterval(30))], now: now) != nil)
        #expect(CrossDeskRestartCheck.blocker(lockOnDisconnect: false, sharing: false, logs: [], now: now) != nil)
    }
}

@Suite("CrossDesk 的设置 config.ini")
struct CrossDeskSettingsTests {
    @Test("认 [Settings] 里的 lock_on_disconnect，真假的写法按 SimpleIni 的 GetBoolValue")
    func lockOnDisconnect() {
        // 真机 11-26 的写法：文件开头带 BOM
        #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "\u{FEFF}[Settings]\nlanguage = 0\nlock_on_disconnect = false\n") == false)
        for value in ["false", "False", "no", "off", "0"] {
            #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "[Settings]\nlock_on_disconnect=\(value)") == false, "\(value)")
        }
        for value in ["true", "yes", "on", "1"] {
            #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "[Settings]\nlock_on_disconnect = \(value)") == true, "\(value)")
        }
    }

    @Test("没写这一项、写在别的节里、认不出的值：按它的默认当作开着")
    func defaultsToOn() {
        #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "[Settings]\nlanguage = 0\n") == true)
        #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "[Other]\nlock_on_disconnect = false\n[Settings]\n") == true)
        #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "[Settings]\nlock_on_disconnect = maybe\n") == true)
        #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "") == true)
    }

    @Test("注释、行首空白、分号开头的行不算")
    func comments() {
        #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "[Settings]\n; lock_on_disconnect = false\n# lock_on_disconnect = false\n") == true)
        #expect(CrossDeskRestartCheck.lockOnDisconnect(config: "[Settings]\n   lock_on_disconnect   =   off   \n") == false)
    }
}

import Foundation
import Testing
@testable import SnugCore

/// 时间都写成「距 t0 的秒数」，断言里的数字能直接对上 5s 稳定期、60s 冷却

private extension AutoRestart {
    /// 没人远程、远控报了没有控制端连着
    mutating func idle(_ stale: Set<DisplayID>?, at seconds: Double) -> Step {
        update(stale: stale, inSession: false, absent: true, now: at(seconds))
    }
}

@Suite("看不到屏时自动重启远控 AutoRestart")
struct AutoRestartTests {
    @Test("常量：稳定期 5s、冷却 60s")
    func constants() {
        #expect(AutoRestart.settle == 5)
        #expect(AutoRestart.cooldown == 60)
    }

    @Test("看得到屏：什么都不做，不记日志")
    func clear() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        #expect(policy.idle(nil, at: 0) == AutoRestart.Step(decision: .clear, logLine: nil))
        #expect(policy.idle([], at: 1).decision == .clear)
    }

    @Test("没人远程：看不到屏持续满 5 秒就重启一次，重启进行中不再发")
    func restartWhenIdle() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        let first = policy.idle([38], at: 0)
        #expect(first.decision == .settling)
        #expect(try #require(first.logLine).contains("#38"))
        #expect(policy.idle([38], at: 4.9) == AutoRestart.Step(decision: .settling, logLine: nil))
        let restart = policy.idle([38], at: 5)
        #expect(restart.decision == .restart)
        #expect(try #require(restart.logLine).contains("没人远程"))
        #expect(policy.isRestarting)
        // 重启要好几秒：这期间每拍照样来，不再发第二次
        #expect(policy.idle([38], at: 5.5) == AutoRestart.Step(decision: .restarting, logLine: nil))
        #expect(policy.idle([38], at: 9).decision == .restarting)
        #expect(policy.finished(reopened: true) == nil)
        #expect(!policy.isRestarting)
        // 重新打开的它启动得比屏晚，看得到了
        #expect(policy.idle(nil, at: 10).decision == .clear)
    }

    @Test("远程中（含断开后等重连）绝不重启：退出它会锁屏。远程结束、它也报了没人连着才重启")
    func skipDuringSession() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        let busy = policy.update(stale: [38], inSession: true, absent: false, now: at(0))
        #expect(busy.decision == .inSession)
        #expect(try #require(busy.logLine).contains("锁屏"))
        // 等重连的十几秒里远控已经报了没人连着，会话层还没说结束：照样不动
        for seconds in stride(from: 0.5, through: 30, by: 0.5) {
            let step = policy.update(stale: [38], inSession: true, absent: seconds > 10, now: at(seconds))
            #expect(step == AutoRestart.Step(decision: .inSession, logLine: nil), "第 \(seconds) 秒")
        }
        // 远程结束：看不到屏早就超过 5 秒了，马上重启
        #expect(policy.idle([38], at: 30.5).decision == .restart)
    }

    @Test("读不到它有没有控制端连着（电源断言读不到）：不算没人，不重启")
    func presenceUnknown() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        let unknown = policy.update(stale: [38], inSession: false, absent: false, now: at(0))
        #expect(unknown.decision == .presenceUnknown)
        #expect(try #require(unknown.logLine).contains("重启 甲远程"))
        for seconds in stride(from: 1.0, through: 120, by: 1) {
            #expect(policy.update(stale: [38], inSession: false, absent: false, now: at(seconds)).decision == .presenceUnknown)
        }
        // 又读得到了、确实没人：重启
        #expect(policy.idle([38], at: 121).decision == .restart)
    }

    @Test("同一批屏只自动重启一次：重启后它还是看不到，留给菜单栏手动点，不再自动重启")
    func noRepeatForSameScreens() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        #expect(policy.finished(reopened: true) == nil)
        // 刚打开时日志还没读回来，按启动时刻判看得到；读回来发现这批里还是没有 #38
        #expect(policy.idle(nil, at: 8).decision == .clear)
        let gaveUp = policy.idle([38], at: 10)
        #expect(gaveUp.decision == .gaveUp)
        #expect(try #require(gaveUp.logLine).contains("重启 甲远程"))
        // 冷却过了也不再来
        for seconds in stride(from: 10.5, through: 300, by: 0.5) {
            #expect(policy.idle([38], at: seconds) == AutoRestart.Step(decision: .gaveUp, logLine: nil), "第 \(seconds) 秒")
        }
    }

    @Test("重启没成（退不掉、打不开）：记一行，这批屏不再自动重启")
    func failedRestart() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        let failure = policy.finished(reopened: false)
        #expect(try #require(failure).contains("重启 甲远程"))
        #expect(!policy.isRestarting)
        #expect(policy.idle([38], at: 20).decision == .gaveUp)
        #expect(policy.idle([38], at: 200).decision == .gaveUp)
    }

    @Test("Snug 又重建了屏（新编号就是新的一批）：可以再重启一次，但两次至少隔 60 秒")
    func cooldownForNewScreens() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        #expect(policy.finished(reopened: true) == nil)
        #expect(policy.idle(nil, at: 8).decision == .clear)
        // 20 秒时屏重建成 #39，它又看不到了
        let cooling = policy.idle([39], at: 20)
        #expect(cooling.decision == .coolingDown)
        #expect(try #require(cooling.logLine).contains("60"))
        #expect(policy.idle([39], at: 64.9) == AutoRestart.Step(decision: .coolingDown, logLine: nil))
        #expect(policy.idle([39], at: 65).decision == .restart)
    }

    @Test("几块屏陆续建好：这一批变了就重新等 5 秒，免得建一块重启一次")
    func settleRestartsWhenScreensChange() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        #expect(policy.idle([38], at: 0).decision == .settling)
        let grown = policy.idle([38, 39], at: 3)
        #expect(grown.decision == .settling)
        #expect(grown.logLine?.contains("#38、#39") == true)
        #expect(policy.idle([38, 39], at: 7.9).decision == .settling)
        #expect(policy.idle([38, 39], at: 8).decision == .restart)
    }

    @Test("等的这 5 秒里又看得到了（日志读回来、它补上了位）：不重启；再看不到时重新等")
    func clearsDuringSettle() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        #expect(policy.idle([38], at: 0).decision == .settling)
        #expect(policy.idle(nil, at: 2).decision == .clear)
        #expect(policy.idle([38], at: 3).decision == .settling)
        #expect(policy.idle([38], at: 7.9).decision == .settling)
        #expect(policy.idle([38], at: 8).decision == .restart)
    }

    @Test("日志只在结论或这一批屏变了时记：每拍都来，同一个结论只记一行")
    func logsOnlyOnChange() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        let lines = (0..<20).compactMap { tick in
            policy.update(stale: [38], inSession: true, absent: false, now: at(Double(tick) * 0.5)).logLine
        }
        #expect(lines.count == 1)
        #expect(policy.update(stale: [39], inSession: true, absent: false, now: at(10)).logLine?.contains("#39") == true)
        #expect(policy.update(stale: [39], inSession: false, absent: false, now: at(10.5)).logLine != nil)
    }
}

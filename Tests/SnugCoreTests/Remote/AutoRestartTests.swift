import Foundation
import Testing
@testable import SnugCore

/// 时间都写成「距 t0 的秒数」，断言里的数字能直接对上 5s 稳定期、60s 冷却

private extension AutoRestart {
    /// 没人远程、现场确认了没人连着
    mutating func idle(_ stale: Set<DisplayID>?, at seconds: Double) -> Step {
        update(stale: stale, inSession: false, blocker: { nil }, now: at(seconds))
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
        #expect(policy.finished(.reopened) == nil)
        #expect(!policy.isRestarting)
        // 重新打开的它启动得比屏晚，看得到了
        #expect(policy.idle(nil, at: 10).decision == .clear)
    }

    @Test("远程中（含断开后等重连）绝不重启，也不去现场确认；远程结束、确认了没人连着才重启")
    func skipDuringSession() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        var asked = 0
        let busy = policy.update(stale: [38], inSession: true, blocker: { asked += 1; return nil }, now: at(0))
        #expect(busy.decision == .inSession)
        #expect(try #require(busy.logLine).contains("锁屏"))
        for seconds in stride(from: 0.5, through: 30, by: 0.5) {
            let step = policy.update(stale: [38], inSession: true, blocker: { asked += 1; return nil }, now: at(seconds))
            #expect(step == AutoRestart.Step(decision: .inSession, logLine: nil), "第 \(seconds) 秒")
        }
        #expect(asked == 0)
        // 远程结束：看不到屏早就超过 5 秒了，马上重启
        #expect(policy.idle([38], at: 30.5).decision == .restart)
    }

    @Test("现场确认不了没人连着（读不到断言、刚有人在连）：不重启，等确认了再重启；还在等稳定期时不去确认")
    func unconfirmed() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        var asked = 0
        #expect(policy.update(stale: [38], inSession: false, blocker: { asked += 1; return "它的日志 1 秒前还在写" }, now: at(0)).decision == .settling)
        #expect(asked == 0)
        let blocked = policy.update(stale: [38], inSession: false, blocker: { asked += 1; return "它的日志 1 秒前还在写" }, now: at(5))
        #expect(blocked.decision == .unconfirmed)
        #expect(try #require(blocked.logLine).contains("它的日志 1 秒前还在写"))
        // 不引导用户去点菜单栏的重启：这时手动点同样可能锁屏
        #expect(blocked.logLine?.contains("菜单栏") == false)
        for seconds in stride(from: 5.5, through: 120, by: 0.5) {
            let step = policy.update(stale: [38], inSession: false, blocker: { "读不到电源断言" }, now: at(seconds))
            #expect(step == AutoRestart.Step(decision: .unconfirmed, logLine: nil), "第 \(seconds) 秒")
        }
        #expect(policy.idle([38], at: 121).decision == .restart)
    }

    @Test("同一批屏只自动重启一次：重启后它还是看不到，留给菜单栏手动点，不再自动重启")
    func noRepeatForSameScreens() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        #expect(policy.finished(.reopened) == nil)
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

    @Test("重启没成（退不掉、打不开、打开又退出）：记一行，这批屏不再自动重启")
    func failedRestart() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        let failure = policy.finished(.failed)
        #expect(try #require(failure).contains("重启 甲远程"))
        #expect(!policy.isRestarting)
        #expect(policy.idle([38], at: 20).decision == .gaveUp)
        #expect(policy.idle([38], at: 200).decision == .gaveUp)
    }

    @Test("退出前现场一查又不行（刚开始远程、刚有人在连、手动重启正在跑）：这次不算重启过，确认了再重启，不进冷却")
    func blockedAtTheLastMoment() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        #expect(policy.finished(.blocked) == nil)
        #expect(policy.update(stale: [38], inSession: false, blocker: { "它的日志 0 秒前还在写" }, now: at(5.5)).decision == .unconfirmed)
        #expect(policy.update(stale: [38], inSession: true, blocker: { nil }, now: at(6)).decision == .inSession)
        #expect(policy.idle([38], at: 30).decision == .restart)
    }

    @Test("自动重启的那一下被手动重启抢了先（撞上「正在重启」）：撤回只撤自动那次，手动记下的这批屏和冷却都留着")
    func blockedByManualRestart() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        policy.noteManualRestart(now: at(5.2))
        #expect(policy.finished(.blocked) == nil)
        #expect(policy.idle([38], at: 30).decision == .gaveUp)
        #expect(policy.idle([39], at: 40).decision == .coolingDown)
        #expect(policy.idle([39], at: 65.2).decision == .restart)
    }

    @Test("手动点过「重启」也算这批屏重启过：之后还是看不到不再自动补一次，冷却从手动那次算")
    func manualRestartCounts() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        policy.noteManualRestart(now: at(2))
        #expect(policy.idle(nil, at: 4).decision == .clear)
        #expect(policy.idle([38], at: 10).decision == .gaveUp)
        // 换了一批屏：冷却从手动重启那一刻算
        #expect(policy.idle([39], at: 20).decision == .coolingDown)
        #expect(policy.idle([39], at: 62).decision == .restart)
    }

    @Test("Snug 又重建了屏（新编号就是新的一批）：可以再重启一次，但两次至少隔 60 秒")
    func cooldownForNewScreens() throws {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        #expect(policy.finished(.reopened) == nil)
        #expect(policy.idle(nil, at: 8).decision == .clear)
        // 20 秒时屏重建成 #39，它又看不到了
        let cooling = policy.idle([39], at: 20)
        #expect(cooling.decision == .coolingDown)
        #expect(try #require(cooling.logLine).contains("60"))
        #expect(policy.idle([39], at: 64.9) == AutoRestart.Step(decision: .coolingDown, logLine: nil))
        #expect(policy.idle([39], at: 65).decision == .restart)
    }

    @Test("在线的屏在两批之间来回跳：重启过的每一批都记得，不会每 60 秒重启一次")
    func alternatingScreens() {
        var policy = AutoRestart(remote: fakeRemote.displayName)
        _ = policy.idle([38], at: 0)
        #expect(policy.idle([38], at: 5).decision == .restart)
        _ = policy.finished(.reopened)
        _ = policy.idle([38, 39], at: 100)
        #expect(policy.idle([38, 39], at: 105).decision == .restart)
        _ = policy.finished(.reopened)
        for start in stride(from: 200.0, through: 800, by: 100) {
            #expect(policy.idle([38], at: start).decision == .gaveUp)
            #expect(policy.idle([38, 39], at: start + 50).decision == .gaveUp)
        }
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
            policy.update(stale: [38], inSession: true, blocker: { nil }, now: at(Double(tick) * 0.5)).logLine
        }
        #expect(lines.count == 1)
        #expect(policy.update(stale: [39], inSession: true, blocker: { nil }, now: at(10)).logLine?.contains("#39") == true)
        #expect(policy.update(stale: [39], inSession: false, blocker: { "读不到电源断言" }, now: at(10.5)).logLine != nil)
    }
}

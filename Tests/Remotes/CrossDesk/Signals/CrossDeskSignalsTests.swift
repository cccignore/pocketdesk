import Foundation
import RemoteCrossDesk
import SnugCore
import Testing

@Suite("CrossDesk 信号")
struct CrossDeskSignalsTests {
    @Test("在场只认「正在共享桌面」的电源断言：有人控制、在抓屏时它才持有；没在跑、没持有、读不到都不算在场")
    func presence() {
        #expect(CrossDeskSignals(running: true, sharing: true).observation()
                == RemoteObservation(present: true, controllers: [], streamedDisplay: nil, evidence: "进程=在 共享桌面=是"))
        #expect(!CrossDeskSignals(running: true, sharing: false).observation().present)
        #expect(!CrossDeskSignals(running: false, sharing: false).observation().present)
        #expect(CrossDeskSignals(running: true, sharing: nil).observation().evidence == "进程=在 共享桌面=读不到")
        #expect(!CrossDeskSignals(running: true, sharing: nil).observation().present)
        // 它这次启动登记了几块显示器，交给核心判断要不要重启它；不改信号快照
        let slotted = CrossDeskSignals(running: true, sharing: false, registered: [1, 22]).observation()
        #expect(slotted.registeredDisplays == [1, 22])
        #expect(slotted.evidence == "进程=在 共享桌面=否")
        #expect(CrossDeskSignals(running: true, sharing: false).observation().registeredDisplays == nil)
    }


    @Test("身份：按记号认注入的事件（界面和注入是同一个程序），资源库排除 CrossDesk 自己")
    func identity() {
        let identity = CrossDeskRemote.identity
        #expect(identity.logName == "CrossDesk")
        #expect(identity.bundleIDs == ["cn.crossdesk.app"])
        let app = "/Applications/CrossDesk.app/Contents/MacOS/CrossDesk"
        #expect(identity.injector.matches(EventOrigin(executablePath: app, userData: 0x4352_4F53_5344_4553)))
        #expect(!identity.injector.matches(EventOrigin(executablePath: app)))
        #expect(!identity.injector.needsExecutablePath)
        #expect(identity.readsDisplaysOnce)
        #expect(identity.needsASCIIInputSource)
    }
}

@Suite("CrossDesk 日志")
struct CrossDeskLogTests {
    private let sample = """
    [2026-11-23 18:00:01.004] [crossdesk] [info] macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'
    [2026-11-23 18:05:35.123] [crossdesk] [info] Start screen capturer, show cursor: true
    [2026-11-23 18:07:10.500] [crossdesk] [info] Last remote controller disconnected; recovering privacy, reason=peer_closed
    [2026-11-23 18:07:10.501] [crossdesk] [info] Stop screen capturer
    [2026-11-23 19:00:00.000] [crossdesk] [info] [screen_capturer_sck_impl.mm:386] macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'
    [2026-11-23 19:00:00.001] [crossdesk] [info] [screen_capturer_sck_impl.mm:386] macOS display discovered: index=1, display_id=7, name='Snug 手机屏'
    [2026-11-23 19:02:00.000] [crossdesk] [warning] something unrelated
    not a log line
    """

    @Test("发布版的日志在级别后面多一段源码位置（v1.7.6 真机）：照样认")
    func sourceLocation() {
        let line = "[2026-11-24 01:43:36.759] [crossdesk] [info] [screen_capturer_sck_impl.mm:386] macOS display discovered: index=1, display_id=13, name='Snug 手机屏'"
        #expect(CrossDeskLogRecord(line: line)?.event == .displayDiscovered(index: 1, display: 13))
        let start = "[2026-11-24 02:00:00.000] [crossdesk] [info] [session_device_manager.cpp:345] Start screen capturer, show cursor: true"
        #expect(CrossDeskLogRecord(line: start)?.event == .captureStarted)
        // 内容本身以方括号开头的不当成源码位置剥掉
        #expect(CrossDeskLogRecord(line: "[2026-11-24 02:00:00.000] [crossdesk] [info] [peer] Start screen capturer")?.event == nil)
    }

    @Test("认出时间、远程开始和结束、启动时读到的显示器；认不出的行跳过")
    func parse() {
        let records = sample.split(separator: "\n").compactMap { CrossDeskLogRecord(line: String($0)) }
        #expect(records.count == 7)
        #expect(records[1].event == .captureStarted)
        #expect(records[2].event == .lastControllerLeft)
        #expect(records[0].event == .displayDiscovered(index: 0, display: 1))
        #expect(records[6].event == nil)
        var expected = DateComponents()
        (expected.year, expected.month, expected.day, expected.hour, expected.minute, expected.second) = (2026, 11, 23, 18, 5, 35)
        let start = Calendar.current.date(from: expected)!.addingTimeInterval(0.123)
        #expect(abs(records[1].date.timeIntervalSince(start)) < 0.001)
    }

    @Test("它看得到哪些显示器：只算最近一次启动时读到的那一批（index 从 0 重新数起就是新的一批）")
    func knownDisplays() {
        let records = sample.split(separator: "\n").compactMap { CrossDeskLogRecord(line: String($0)) }
        #expect(CrossDeskLogRecord.lastEnumeration(records) == [1, 7])
        #expect(CrossDeskLogRecord.lastEnumeration(Array(records.prefix(4))) == [1])
        #expect(CrossDeskLogRecord.lastEnumeration([]).isEmpty)
    }

    @Test("这次启动登记的那一批：取启动时刻之后开始、抓屏初始化成功了的最后一批；刚启动还没写完、初始化失败为 nil")
    func enumerationSinceLaunch() throws {
        let log = """
        [2026-11-24 03:00:00.000] [crossdesk] [info] [screen_capturer_sck_impl.mm:426] macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'
        [2026-11-24 03:00:00.001] [crossdesk] [info] [screen_capturer_sck_impl.mm:426] macOS display discovered: index=1, display_id=22, name='Snug 手机屏'
        [2026-11-24 03:00:00.002] [crossdesk] [info] [session_device_manager.cpp:303] Init screen capturer success
        [2026-11-24 04:00:00.000] [crossdesk] [info] [screen_capturer_sck_impl.mm:426] macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'
        """
        let records = log.split(separator: "\n").compactMap { CrossDeskLogRecord(line: String($0)) }
        #expect(records[2].event == .captureInitialized)
        let first = records[0].date
        // 03:00 那次启动：登记了 #1、#22
        #expect(CrossDeskLogRecord.enumeration(since: first.addingTimeInterval(-1), in: Array(records.prefix(3))) == [1, 22])
        // 只写了一半（index=1 和初始化成功还没写）
        #expect(CrossDeskLogRecord.enumeration(since: first.addingTimeInterval(-1), in: Array(records.prefix(1))) == nil)
        // 04:00 又启动了一次，还没写完：不拿上一次的顶替
        #expect(CrossDeskLogRecord.enumeration(since: first.addingTimeInterval(3599), in: records) == nil)
        #expect(CrossDeskLogRecord.enumeration(since: .distantPast, in: []) == nil)
    }
}

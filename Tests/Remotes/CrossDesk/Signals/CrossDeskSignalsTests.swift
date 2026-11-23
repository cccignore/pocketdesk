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
    }
}

@Suite("CrossDesk 日志")
struct CrossDeskLogTests {
    private let sample = """
    [2026-11-23 18:00:01.004] [crossdesk] [info] macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'
    [2026-11-23 18:05:35.123] [crossdesk] [info] Start screen capturer, show cursor: true
    [2026-11-23 18:07:10.500] [crossdesk] [info] Last remote controller disconnected; recovering privacy, reason=peer_closed
    [2026-11-23 18:07:10.501] [crossdesk] [info] Stop screen capturer
    [2026-11-23 19:00:00.000] [crossdesk] [info] macOS display discovered: index=0, display_id=1, name='Built-in Retina Display'
    [2026-11-23 19:00:00.001] [crossdesk] [info] macOS display discovered: index=1, display_id=7, name='Snug 手机屏'
    [2026-11-23 19:02:00.000] [crossdesk] [warning] something unrelated
    not a log line
    """

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
}

import Foundation
import RemoteCrossDesk
import SnugCore
import Testing

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func facts(_ change: (inout CrossDeskCheck.Facts) -> Void = { _ in }) -> CrossDeskCheck.Facts {
    var f = CrossDeskCheck.Facts(version: "1.4.0", running: true, signals: CrossDeskSignals(running: true, sharing: false),
                                 logReadable: true, enumerated: [1, 7], onlineSnugDisplays: [7],
                                 sessionsInLog: 2, detectionsInSnugLog: 2)
    change(&f)
    return f
}

private func status(_ title: String, in items: [CrossDeskCheck.Item]) -> CrossDeskCheck.Status? {
    items.first { $0.title == title }?.status
}

@Suite("CrossDesk 兼容自检")
struct CrossDeskCheckTests {
    @Test("一切正常：装了、在跑、读得到断言、启动时读到了在线的 Snug 屏、远程都察觉到了")
    func allGood() {
        let items = CrossDeskCheck.evaluate(facts())
        #expect(items.allSatisfy { $0.status == .ok || $0.status == .info })
    }

    @Test("Snug 的屏不在 CrossDesk 启动时读到的那一批里：报错，说明要重启 CrossDesk")
    func snugScreenUnseen() {
        let items = CrossDeskCheck.evaluate(facts { $0.enumerated = [1]; $0.onlineSnugDisplays = [7, 9] })
        let item = items.first { $0.title == "看得到 Snug 的屏" }
        #expect(item?.status == .fail)
        #expect(item?.detail.contains("#7、#9") == true)
        #expect(item?.detail.contains("重启 CrossDesk") == true)
    }

    @Test("没装是错；没在跑、此刻没有 Snug 的屏在线、读不到日志只提醒")
    func missingPieces() {
        #expect(status("CrossDesk", in: CrossDeskCheck.evaluate(facts { $0.version = nil; $0.running = false })) == .fail)
        #expect(status("进程", in: CrossDeskCheck.evaluate(facts { $0.running = false })) == .warn)
        #expect(status("看得到 Snug 的屏", in: CrossDeskCheck.evaluate(facts { $0.onlineSnugDisplays = [] })) == .warn)
        #expect(status("看得到 Snug 的屏", in: CrossDeskCheck.evaluate(facts { $0.logReadable = false })) == .warn)
    }

    @Test("读不到电源断言是错（在场全靠它）；CrossDesk 远程过、Snug 一次都没察觉也是错")
    func detectionBroken() {
        #expect(status("共享桌面断言", in: CrossDeskCheck.evaluate(facts { $0.signals.sharing = nil })) == .fail)
        #expect(status("连接检测", in: CrossDeskCheck.evaluate(facts { $0.detectionsInSnugLog = 0 })) == .fail)
        #expect(status("连接检测", in: CrossDeskCheck.evaluate(facts { $0.sessionsInLog = 0; $0.detectionsInSnugLog = 0 })) == .info)
    }

    @Test("报告：标题、结论、逐项一行")
    func report() {
        let text = CrossDeskCheck.report(CrossDeskCheck.evaluate(facts { $0.enumerated = [1] }), hours: 6, at: now)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0].hasPrefix("CrossDesk 兼容自检 · "))
        #expect(lines[1] == "结论：发现 1 项问题")
        #expect(lines.contains { $0.hasPrefix("❌ 看得到 Snug 的屏：") })
    }
}

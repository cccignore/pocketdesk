// --check-remote crossdesk [小时]：CrossDesk 兼容自检（scripts/snug remote-check crossdesk 调）。收集事实交给 CrossDeskCheck 判定、打出报告。
// 只读：不碰 CrossDesk、不碰屏幕
import CoreGraphics
import Foundation
import RemoteCrossDesk
import SnugCore
import SnugSystem

@MainActor
package enum CrossDeskCheckRun {
    package static func run(hours: Int) -> Int32 {
        let now = Date()
        let since = now.addingTimeInterval(-TimeInterval(hours) * 3600)
        let apps = CrossDeskApp.running()
        let pids = apps.map(\.processIdentifier)
        let sharing = try? CrossDeskApp.sharing(pids: pids).get()
        let lines = CrossDeskApp.logLines()
        let records = (lines ?? []).compactMap(CrossDeskLogRecord.init(line:))
        let snug = SnugLogDigest(lines: readSnugLog(), since: since, remote: CrossDeskRemote.identity.logName)
        let facts = CrossDeskCheck.Facts(
            version: CrossDeskApp.installedVersion(), running: !pids.isEmpty,
            signals: CrossDeskSignals(running: !pids.isEmpty, sharing: sharing),
            logReadable: lines != nil, enumerated: CrossDeskLogRecord.lastEnumeration(records),
            onlineSnugDisplays: Set((Screens.online() ?? []).filter { CGDisplayVendorNumber($0) == ScreenSpec.vendorID }),
            onlineDisplays: Set(Screens.online() ?? []),
            sessionsInLog: records.filter { $0.date >= since && $0.event == .captureStarted }.count,
            detectionsInSnugLog: snug.detections.count)
        let items = CrossDeskCheck.evaluate(facts)
        print(CrossDeskCheck.report(items, hours: hours, at: now))
        print("")
        print("屏幕：")
        CrossDeskDump.displayLines().forEach { print($0) }
        return items.contains { $0.status == .fail } ? 1 : 0
    }

    /// 滚动过的旧日志在前（见 FileLogSink），读不到的跳过
    private static func readSnugLog() -> [Substring] {
        let current = SnugPaths.standard.logFile
        let rotated = current.deletingLastPathComponent().appendingPathComponent(current.lastPathComponent + ".1")
        return [rotated, current].flatMap { url -> [Substring] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n")
        }
    }
}

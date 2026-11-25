// --dump-remote crossdesk：打印从 CrossDesk 读到的东西和此刻的屏幕。只读，不碰 CrossDesk、不碰屏幕
import CoreGraphics
import Foundation
import RemoteCrossDesk
import SnugCore
import SnugSystem

@MainActor
package enum CrossDeskDump {
    package static func run() -> Int32 {
        print("CrossDesk：\(CrossDeskApp.installedVersion().map { "版本 \($0)" } ?? "没装")")
        let apps = CrossDeskApp.running()
        print("进程：\(apps.isEmpty ? "没在运行" : apps.map { "pid \($0.processIdentifier)（\($0.launchDate.map(clock) ?? "启动时刻未知") 启动）" }.joined(separator: "、"))")
        let started = ProcessInfo.processInfo.systemUptime
        let sharing = CrossDeskApp.sharing(pids: apps.map(\.processIdentifier))
        let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
        switch sharing {
        case .success(let held): print("共享桌面断言：\(held ? "持有（有控制端连着）" : "没持有")（查询 \(String(format: "%.1f", elapsed)) 毫秒）")
        case .failure(let failure): print("共享桌面断言：读不到（\(failure)）")
        }
        print("屏幕：")
        displayLines().forEach { print($0) }
        guard let lines = CrossDeskApp.logLines() else {
            print("日志：读不到 \(CrossDeskLogRecord.path.path)")
            return apps.isEmpty ? 1 : 0
        }
        let records = lines.compactMap(CrossDeskLogRecord.init(line:))
        print("它最近一次启动时读到的显示器：\(CrossDeskLogRecord.lastEnumeration(records).map { "#\($0)" }.joined(separator: "、"))")
        print("日志里最近的远程：")
        for record in records.filter({ $0.event == .captureStarted || $0.event == .lastControllerLeft }).suffix(10) {
            print("  \(clock(record.date)) \(record.event == .captureStarted ? "开始（有控制端连上）" : "结束（最后一个控制端断开）")")
        }
        return apps.isEmpty ? 1 : 0
    }

    /// 此刻在线的屏，一行一块
    static func displayLines() -> [String] {
        (Screens.online() ?? []).map { id in
            let mine = CGDisplayVendorNumber(id) == ScreenSpec.vendorID ? "（PocketDesk 的屏）" : ""
            return "  #\(id) \(Screens.name(of: id))\(mine) \(DisplayMode.describe(id))"
        }
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

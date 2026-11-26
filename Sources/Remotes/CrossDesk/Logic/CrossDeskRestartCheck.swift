// 退出 CrossDesk 之前现场确认（自动重启它用，见 SnugCore 的 AutoRestart）。两件事分开管：
// - 不锁屏：它开着「连接断开后锁屏」（lock_on_disconnect，默认开）时，有控制端连着就退出它会锁屏（收尾时先断开所有会话再
//   HandleScreenLock，gui_application.cpp 的 Cleanup）。有没有控制端连着从外面没法完全确认：控制端一连上锁屏就记下了
//   （peer_event_handler.cpp 的 disconnect_lock_.Connected），电源断言要等开始抓屏才持有，没有屏幕录制权限时一直不持有，日志也不写。
//   所以只在这一项关着时才退出它：关着时锁屏请求根本不会记下（disconnect_lock_policy.h 两头都看这一项），退出它不可能锁屏
// - 不断掉远程：读得到电源断言、没持有（在抓屏的控制端都持有），两份日志都静了 quietLogs（连接握手时 minirtc.log 一直在写，
//   真机 11-26 15:35：48.613 有人连入，49.998 才持有断言）
import Foundation

package enum CrossDeskRestartCheck {
    /// 两份日志都这么久没写过，才算没人正在连
    package static let quietLogs: TimeInterval = 10
    /// 要看的日志：它自己的，和它的网络库 minirtc 的（同一个目录）
    package static let logNames = ["crossdesk.log", "minirtc.log"]

    /// lockOnDisconnect：它的「连接断开后锁屏」，nil = 读不到设置。sharing：「正在共享桌面」的电源断言，nil = 读不到。
    /// logs：每份日志最后写入的时刻（墙钟），nil = 读不到。可以退出它交 nil，不行交原因（写进日志、手动重启的弹窗）
    package static func blocker(lockOnDisconnect: Bool?, sharing: Bool?, logs: [(name: String, writtenAt: Date?)], now: Date) -> String? {
        switch lockOnDisconnect {
        case nil:
            return "读不到它的设置（~/.cache/CrossDesk/config.ini），按它的默认当作开着「连接断开后锁屏」，有控制端连着时退出它会锁屏"
        case true?:
            return "它开着「连接断开后锁屏」：有控制端连着时退出它会锁屏，有没有控制端连着又没法完全确认。在 CrossDesk 设置里关掉这一项才会自动重启"
        case false?:
            break
        }
        guard let sharing else { return "读不到电源断言，确认不了没人连着" }
        if sharing { return "有控制端连着（共享桌面=是）" }
        guard !logs.isEmpty else { return "找不到它的日志，确认不了没人正在连" }
        if let missing = logs.first(where: { $0.writtenAt == nil }) { return "读不到它的日志 \(missing.name) 的写入时刻，确认不了没人正在连" }
        let latest = logs.compactMap { log in log.writtenAt.map { (log.name, $0) } }.max { $0.1 < $1.1 }
        guard let (name, writtenAt) = latest else { return "找不到它的日志，确认不了没人正在连" }
        let quiet = now.timeIntervalSince(writtenAt)
        guard quiet >= quietLogs else {
            return quiet < 0 ? "它的日志 \(name) 写入时刻在未来（改过系统时间？），确认不了没人正在连"
                             : "它的日志 \(name) \(Int(quiet)) 秒前还在写，可能有人正在连"
        }
        return nil
    }

    /// config.ini 里 [Settings] 的 lock_on_disconnect。它用 SimpleIni 读（config_center.cpp 的 GetBoolValue，默认 true）：
    /// true/yes/on/1 为真，false/no/off/0 为假，大小写不论；没写、认不出都按默认当作开着
    package static func lockOnDisconnect(config: String) -> Bool {
        var section = ""
        var value: Bool?
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}")))
            if line.hasPrefix("[") {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                continue
            }
            guard section == "Settings", !line.hasPrefix(";"), !line.hasPrefix("#"), let equals = line.firstIndex(of: "="),
                  line[..<equals].trimmingCharacters(in: .whitespaces) == "lock_on_disconnect" else { continue }
            switch line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "on", "1": value = true
            case "false", "no", "off", "0": value = false
            default: value = nil
            }
        }
        return value ?? true
    }
}

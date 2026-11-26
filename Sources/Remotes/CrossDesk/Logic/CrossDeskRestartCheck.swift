// 退出 CrossDesk 之前现场确认没人连着、也没人正在连（自动重启它用，见 SnugCore 的 AutoRestart）。
// 有控制端连着时退出它会锁屏：它收尾时先断开所有会话再 HandleScreenLock（gui_application.cpp 的 Cleanup）。
// 只看电源断言不够：控制端一连上锁屏就记下了（peer_event_handler.cpp 的 disconnect_lock_.Connected），断言却要等分辨率设好、
// 开始抓屏才持有（session_device_manager.cpp，等分辨率最多 2 秒，见 display_resolution_state.h；抓屏起不来时每秒重试、一直不持有）。
// 这段时间它的日志一直在写：minirtc.log 从「Remote user joined transmission」起写握手，crossdesk.log 写抓屏重试
// （真机 11-26 15:35：48.613 有人连入，49.998 才持有断言）。没人时两份日志都静着，所以再要求两份日志都静了 quietLogs
import Foundation

package enum CrossDeskRestartCheck {
    /// 两份日志都这么久没写过，才算没人正在连
    package static let quietLogs: TimeInterval = 10
    /// 要看的日志：它自己的，和它的网络库 minirtc 的（同一个目录）
    package static let logNames = ["crossdesk.log", "minirtc.log"]

    /// sharing：「正在共享桌面」的电源断言，nil = 读不到。logs：每份日志最后写入的时刻（墙钟），nil = 读不到。
    /// 可以退出它交 nil，不行交原因（写进日志）
    package static func blocker(sharing: Bool?, logs: [(name: String, writtenAt: Date?)], now: Date) -> String? {
        guard let sharing else { return "读不到电源断言" }
        if sharing { return "有控制端连着（共享桌面=是）" }
        guard !logs.isEmpty else { return "找不到它的日志" }
        if let missing = logs.first(where: { $0.writtenAt == nil }) { return "读不到它的日志 \(missing.name) 的写入时刻" }
        let latest = logs.compactMap { log in log.writtenAt.map { (log.name, $0) } }.max { $0.1 < $1.1 }
        guard let (name, writtenAt) = latest else { return "找不到它的日志" }
        let quiet = now.timeIntervalSince(writtenAt)
        guard quiet >= quietLogs else {
            return quiet < 0 ? "它的日志 \(name) 写入时刻在未来（改过系统时间？）"
                             : "它的日志 \(name) \(Int(quiet)) 秒前还在写，可能有人正在连"
        }
        return nil
    }
}

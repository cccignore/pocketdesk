// CrossDesk 的适配器：每拍查一次它在不在运行、持不持有「正在共享桌面」的电源断言；
// 换了进程读一次它的日志，看这次启动登记了几块显示器（之后最多切得到这么多块）
import AppKit
import RemoteCrossDesk
import SnugCore

@MainActor
package final class CrossDeskRemoteAdapter: RemoteAdapter {
    package static let identity = CrossDeskRemote.identity
    /// 上一拍读电源断言失败的原因：只在读得到、读不到之间变的时候记日志，不每拍刷一行
    private var readFailure: AssertionReadFailure?
    /// 这个进程这次启动登记了几块显示器（读到了就不再读）
    private var slots: (pid: pid_t, count: Int)?
    /// 上次读日志找这一批：刚启动时它还没写，隔 slotRetry 秒再读，不每拍读
    private var lastSlotRead: (pid: pid_t, at: TimeInterval)?
    private static let slotRetry: TimeInterval = 2

    package init() {}

    package func start() {}
    package func stop() {}

    package func sample(wallClock: Date) -> RemoteObservation {
        let apps = CrossDeskApp.running()
        let pids = apps.map(\.processIdentifier)
        let sharing: Bool?
        switch CrossDeskApp.sharing(pids: pids) {
        case .success(let held):
            if let failure = readFailure { Log.info("电源断言又读得到了（之前：\(failure)）") }
            readFailure = nil
            sharing = held
        case .failure(let failure):
            if readFailure == nil { Log.warn("读不到电源断言（\(failure)），CrossDesk 在不在被控制算读不到，读回来之前不再重复记") }
            readFailure = failure
            sharing = nil
        }
        return CrossDeskSignals(running: !pids.isEmpty, sharing: sharing, slots: slotCount(of: apps.first)).observation()
    }

    /// 这次启动登记了几块显示器：取它启动之后日志里读到的那一批。没在运行、还没写、日志读不到都是 nil
    private func slotCount(of app: NSRunningApplication?) -> Int? {
        guard let app else {
            slots = nil
            return nil
        }
        let pid = app.processIdentifier
        if let slots, slots.pid == pid { return slots.count }
        let uptime = ProcessInfo.processInfo.systemUptime
        if let last = lastSlotRead, last.pid == pid, uptime - last.at < Self.slotRetry { return nil }
        lastSlotRead = (pid, uptime)
        // 日志的时间戳精确到毫秒，系统记的启动时刻和它差不了一秒；放宽一秒，不会把上一次启动的那一批算进来（两次启动隔得更久）
        guard let launched = app.launchDate, let lines = CrossDeskApp.logLines(),
              let batch = CrossDeskLogRecord.enumeration(since: launched.addingTimeInterval(-1), in: lines.compactMap(CrossDeskLogRecord.init(line:)))
        else { return nil }
        slots = (pid, batch.count)
        Log.info("CrossDesk（pid \(pid)）这次启动登记了 \(batch.count) 块显示器：\(batch.map { "#\($0)" }.joined(separator: "、"))")
        return batch.count
    }

    package nonisolated static func makeTouchShaper() -> any TouchShaper { CrossDeskShaper() }
}

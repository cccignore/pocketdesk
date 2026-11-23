// CrossDesk 的适配器：每拍查一次它在不在运行、持不持有「正在共享桌面」的电源断言；
// 换了进程读一次它的日志（在后台线程上），看这次启动登记了哪些显示器（Snug 的屏切不切得到见 RegisteredDisplays）
import AppKit
import RemoteCrossDesk
import SnugCore

@MainActor
package final class CrossDeskRemoteAdapter: RemoteAdapter {
    package static let identity = CrossDeskRemote.identity
    /// 上一拍读电源断言失败的原因：只在读得到、读不到之间变的时候记日志，不每拍刷一行
    private var readFailure: AssertionReadFailure?
    /// 这个进程这次启动登记的显示器（读到了就不再读）
    private var registered: (pid: pid_t, displays: [DisplayID])?
    /// 读日志找这一批：日志最多约 20MB，放到后台读，读完回主线程记下。刚启动时它还没写完，隔 readRetry 秒再读，
    /// 读 readTries 次还没有（抓屏初始化失败、启动那段已经滚动掉了）就不读了，核心按它的启动时刻判断
    private var reading: (pid: pid_t, tries: Int, next: TimeInterval, inFlight: Bool)?
    private static let readRetry: TimeInterval = 2
    private static let readTries = 5

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
        return CrossDeskSignals(running: !pids.isEmpty, sharing: sharing, registered: registeredDisplays(of: apps.first)).observation()
    }

    /// 这次启动登记的显示器：取它启动之后日志里写完的那一批。没在运行、还在读、没读到都是 nil
    private func registeredDisplays(of app: NSRunningApplication?) -> [DisplayID]? {
        guard let app else {
            registered = nil
            reading = nil
            return nil
        }
        let pid = app.processIdentifier
        if let registered, registered.pid == pid { return registered.displays }
        if reading?.pid != pid { reading = (pid, 0, 0, false) }
        guard var read = reading, !read.inFlight, read.tries < Self.readTries,
              ProcessInfo.processInfo.systemUptime >= read.next, let launched = app.launchDate else { return nil }
        read.tries += 1
        read.inFlight = true
        reading = read
        // 日志的时间戳精确到毫秒，系统记的启动时刻和它差不了一秒；放宽一秒，不会把上一次启动的那一批算进来（两次启动隔得更久）
        let since = launched.addingTimeInterval(-1)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let batch = CrossDeskApp.enumerationLines().flatMap { lines in
                CrossDeskLogRecord.enumeration(since: since, in: lines.compactMap(CrossDeskLogRecord.init(line:)))
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finishRead(pid: pid, batch: batch) } }
        }
        return nil
    }

    private func finishRead(pid: pid_t, batch: [DisplayID]?) {
        guard var read = reading, read.pid == pid else { return }
        read.inFlight = false
        read.next = ProcessInfo.processInfo.systemUptime + Self.readRetry
        reading = read
        if let batch {
            registered = (pid, batch)
            Log.info("CrossDesk（pid \(pid)）这次启动登记了 \(batch.count) 块显示器：\(batch.map { "#\($0)" }.joined(separator: "、"))")
        } else if read.tries >= Self.readTries {
            Log.warn("读了 \(read.tries) 次 CrossDesk 的日志，都没找到它（pid \(pid)）这次启动登记的显示器"
                     + "（抓屏初始化失败、或启动那段已经滚动掉了），按它的启动时刻判断要不要重启它")
        }
    }

    package nonisolated static func makeTouchShaper() -> any TouchShaper { CrossDeskShaper() }
}

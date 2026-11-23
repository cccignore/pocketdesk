// CrossDesk 的适配器：每拍查一次它在不在运行、持不持有「正在共享桌面」的电源断言
import Foundation
import RemoteCrossDesk
import SnugCore

@MainActor
package final class CrossDeskRemoteAdapter: RemoteAdapter {
    package static let identity = CrossDeskRemote.identity
    /// 上一拍读电源断言失败的原因：只在读得到、读不到之间变的时候记日志，不每拍刷一行
    private var readFailure: AssertionReadFailure?

    package init() {}

    package func start() {}
    package func stop() {}

    package func sample(wallClock: Date) -> RemoteObservation {
        let pids = CrossDeskApp.running().map(\.processIdentifier)
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
        return CrossDeskSignals(running: !pids.isEmpty, sharing: sharing).observation()
    }

    package nonisolated static func makeTouchShaper() -> any TouchShaper { CrossDeskShaper() }
}

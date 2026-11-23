import Foundation
import RemoteCrossDesk
import SnugCore

/// CrossDesk：只有一路信号（「正在共享桌面」的电源断言），认不出控制端、报不了推流屏
struct CrossDeskDriver: RemoteDriver {
    let identity = CrossDeskRemote.identity
    let namesControllers = false
    let reportsStreamedDisplay = false
    let injectedOrigin = EventOrigin(executablePath: "/Applications/CrossDesk.app/Contents/MacOS/CrossDesk", userData: CrossDeskRemote.injectedMarker)
    let appBundleID = CrossDeskRemote.bundleID

    func idle() -> RemoteObservation { CrossDeskSignals(running: true, sharing: false).observation() }
    func unreadable() -> RemoteObservation { CrossDeskSignals(running: true, sharing: nil).observation() }
    func connected(controllers: [String]) -> RemoteObservation { CrossDeskSignals(running: true, sharing: true).observation() }
    func streaming(_ display: DisplayID) -> RemoteObservation { CrossDeskSignals(running: true, sharing: true).observation() }
}

// CrossDesk 的身份。各处认 CrossDesk（感知、手势只接管它发来的操作、App 资源库里排除它）都认这里
import Foundation
import SnugCore

package enum CrossDeskRemote {
    /// CrossDesk 主程序。Mac 上只有这一个进程：界面、抓屏、注入键鼠都在里面（没有后台服务）
    package static let bundleID = "cn.crossdesk.app"
    /// 它给每个注入的鼠标、键盘事件写的 eventSourceUserData（'CROSSDES'，源码 platform/macos/input/mac_injected_event.h）
    package static let injectedMarker: Int64 = 0x4352_4F53_5344_4553
    /// 有控制端连着、在抓屏时它持有的电源断言的名字（源码 screen_sharing_power.cpp，防系统和显示器空闲睡眠各一个，同名）
    package static let sharingAssertion = "CrossDesk is sharing the desktop"

    /// 交给核心的身份：界面和注入是同一个程序，按记号认注入的事件；它只在启动时读一次显示器（源码 screen_capturer_sck_impl.mm），屏要常驻
    package static let identity = RemoteIdentity(logName: "CrossDesk", displayName: "CrossDesk", bundleIDs: [bundleID],
                                                injector: InjectedEventSource(marker: injectedMarker), readsDisplaysOnce: true)
}

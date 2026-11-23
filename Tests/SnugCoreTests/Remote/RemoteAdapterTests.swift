import Foundation
import Testing
@testable import SnugCore

@Suite("远控端口 RemoteAdapter")
struct RemoteAdapterTests {
    @Test("按进程认：只认可执行文件名完全对上的进程；读不到路径、同名目录、名字只是前缀都不认")
    func injectedByProcess() {
        let source = fakeRemote.injector
        #expect(source.matches(EventOrigin(executablePath: "/Applications/甲.app/Contents/Helpers/JiaServer")))
        #expect(source.matches(EventOrigin(executablePath: "JiaServer")))
        #expect(!source.matches(EventOrigin(executablePath: "")))
        #expect(!source.matches(EventOrigin(executablePath: "/Applications/甲.app/Contents/MacOS/甲")))
        #expect(!source.matches(EventOrigin(executablePath: "/tmp/JiaServer/helper")))
        #expect(!source.matches(EventOrigin(executablePath: "/Applications/甲.app/Contents/Helpers/JiaServerAgent")))
        #expect(!source.matches(EventOrigin(executablePath: "/Applications/甲.app/Contents/Helpers/jiaserver")))
        #expect(source.needsExecutablePath)
    }

    @Test("按进程认：事件自带什么记号都不影响（UU 不写记号，判法和以前一样）")
    func processIgnoresMarker() {
        let source = fakeRemote.injector
        #expect(source.matches(EventOrigin(executablePath: "/x/JiaServer", userData: 0x1234)))
        #expect(!source.matches(EventOrigin(executablePath: "/x/YiServer", userData: 0x1234)))
    }

    @Test("按记号认：记号对上就认，不管是哪个进程发的；记号不对、没有记号都不认，也不用查进程路径")
    func injectedByMarker() {
        let source = markedRemote.injector
        #expect(source.matches(EventOrigin(executablePath: "/Applications/丙.app/Contents/MacOS/丙", userData: bingMarker)))
        #expect(source.matches(EventOrigin(executablePath: "", userData: bingMarker)))
        #expect(!source.matches(EventOrigin(executablePath: "/Applications/丙.app/Contents/MacOS/丙")))
        #expect(!source.matches(EventOrigin(executablePath: "", userData: bingMarker + 1)))
        #expect(!source.needsExecutablePath)
    }

    @Test("日志里的写法：按进程的写进程名（只登记 UU 时开启手势的日志逐字不变），按记号的写十六进制记号")
    func injectorDescription() {
        #expect(fakeRemote.injector.description == "JiaServer")
        #expect(markedRemote.injector.description == "记号 0x42494E47")
    }
}

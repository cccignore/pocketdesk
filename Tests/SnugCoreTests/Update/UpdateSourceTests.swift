import Foundation
import Testing
@testable import SnugCore

@Suite("更新源 UpdateSource")
struct UpdateSourceTests {
    private let version = Version(major: 3, minor: 0, patch: 0)

    @Test("PocketDesk 只有 GitHub 一个源：cccignore/pocketdesk 最新 Release 的 update.json，各版本 Release 下的包")
    func github() {
        #expect(UpdateSource.allCases == [.github])
        let source = UpdateSource.github
        #expect(source.feedURL.absoluteString == "https://github.com/cccignore/pocketdesk/releases/latest/download/update.json")
        #expect(source.url(of: "PocketDesk-3.0.0.pack", in: version).absoluteString
            == "https://github.com/cccignore/pocketdesk/releases/download/v3.0.0/PocketDesk-3.0.0.pack")
        #expect(source.downloadPage.absoluteString == "https://github.com/cccignore/pocketdesk/releases/latest")
    }
}

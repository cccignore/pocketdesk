// 更新源：从哪取 update.json 和包。PocketDesk 只发 GitHub Release（cccignore/pocketdesk），没有国内源。
// Snug 的腾讯云源指向上游的包，迁来的配置里选着它时按不认识的源处理、落回 GitHub（AppConfig 解码时）
import Foundation

public enum UpdateSource: String, Codable, CaseIterable, Sendable {
    /// GitHub Release
    case github

    public var title: String {
        switch self {
        case .github: "GitHub"
        }
    }

    private static let githubBase = URL(string: "https://github.com/cccignore/pocketdesk/releases")!

    /// 最新发布的 update.json
    public var feedURL: URL {
        switch self {
        case .github: Self.githubBase.appendingPathComponent("latest/download/update.json")
        }
    }

    /// 某个版本下的文件
    public func url(of file: String, in version: Version) -> URL {
        switch self {
        case .github: Self.githubBase.appendingPathComponent("download/v\(version)").appendingPathComponent(file)
        }
    }

    /// 自己换不了时，请用户手动下载的地方
    public var downloadPage: URL {
        switch self {
        case .github: Self.githubBase.appendingPathComponent("latest")
        }
    }
}

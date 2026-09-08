import Foundation
import XCTest
@testable import RoutinUsage

final class GitHubUpdateServiceTests: XCTestCase {
    func testRelease列表只选择macOS版本() async throws {
        let body = """
        [
          {"tag_name":"android-v9.0.0","html_url":"https://github.com/dick86114/MyToken/releases/tag/android-v9.0.0","assets":[{"name":"MyToken-9.0.0-android.apk","browser_download_url":"https://example.com/app.apk"}]},
          {"tag_name":"macos-v5.2.0","html_url":"https://github.com/dick86114/MyToken/releases/tag/macos-v5.2.0","assets":[{"name":"MyToken-5.2.0-arm64.dmg","browser_download_url":"https://example.com/app.dmg"}],"body":"macOS 更新"}
        ]
        """
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data(body.utf8))
        }
        let service = GitHubUpdateService(session: stub.session, currentVersion: "5.1.0")

        let update = try await service.checkForUpdate()

        XCTAssertEqual(update?.version, "5.2.0")
        XCTAssertEqual(update?.notes, "macOS 更新")
        XCTAssertEqual(update?.downloadURL.absoluteString, "https://example.com/app.dmg")
    }

    func test发现较新Release并选择DMG资源() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data(#"{"tag_name":"v1.2.0","html_url":"https://github.com/dick86114/MyToken/releases/tag/v1.2.0","published_at":"2026-09-03T12:30:00Z","body":"修复问题","assets":[{"name":"MyToken.dmg","browser_download_url":"https://example.com/MyToken.dmg"}]}"#.utf8))
        }
        let logger = UpdateLogWriter()
        let service = GitHubUpdateService(
            session: stub.session,
            currentVersion: "1.1.9",
            logWriter: logger
        )

        let update = try await service.checkForUpdate()

        XCTAssertEqual(stub.registration.lastRequest?.url, GitHubUpdateService.releasesURL)
        XCTAssertEqual(update?.version, "1.2.0")
        XCTAssertEqual(update?.downloadURL.absoluteString, "https://example.com/MyToken.dmg")
        XCTAssertEqual(
            update?.publishedAt,
            Date(timeIntervalSince1970: 1_788_438_600)
        )
        let events = await logger.events
        XCTAssertTrue(events.contains { $0 == "update_check_succeeded" })
    }

    func test相同或更旧Release不提示更新() async throws {
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data(#"{"tag_name":"v1.2.0","html_url":"https://github.com/dick86114/MyToken/releases/tag/v1.2.0","assets":[{"name":"MyToken.dmg","browser_download_url":"https://example.com/MyToken.dmg"}]}"#.utf8))
        }
        let service = GitHubUpdateService(session: stub.session, currentVersion: "1.2.0")

        let update = try await service.checkForUpdate()
        XCTAssertNil(update)
    }

    func testGitHubAPI限流时回退到AtomFeed() async throws {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/v5.0.0</id>
            <updated>2026-09-03T13:38:39Z</updated>
            <link rel="alternate" href="https://github.com/dick86114/MyToken/releases/tag/v5.0.0" />
            <title>MyToken v5.0.0</title>
            <content type="html">&lt;p&gt;更换品牌名&lt;/p&gt;</content>
          </entry>
          <entry>
            <id>tag:github.com,2008:Repository/1/v3.0.0</id>
            <updated>2026-08-12T05:38:50Z</updated>
            <link rel="alternate" href="https://github.com/dick86114/MyToken/releases/tag/v3.0.0" />
            <title>MyToken v3.0.0</title>
            <content type="html">&lt;ol&gt;&lt;li&gt;旧版本日志&lt;/li&gt;&lt;/ol&gt;</content>
          </entry>
        </feed>
        """
        let stub = URLProtocolStub.makeSession { request in
            let url = try XCTUnwrap(request.url)
            if url == GitHubUpdateService.releasesURL {
                let response = try XCTUnwrap(
                    HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)
                )
                return (response, Data(#"{"message":"API rate limit exceeded"}"#.utf8))
            }
            if url == GitHubUpdateService.releasesAtomURL {
                let response = try XCTUnwrap(
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                )
                return (response, Data(atom.utf8))
            }
            XCTAssertEqual(request.httpMethod, "HEAD")
            let response = try XCTUnwrap(
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data())
        }
        let service = GitHubUpdateService(session: stub.session, currentVersion: "1.2.0")

        let update = try await service.checkForUpdate()

        XCTAssertEqual(update?.version, "5.0.0")
        XCTAssertEqual(
            update?.publishedAt,
            Date(timeIntervalSince1970: 1_788_442_719)
        )
        XCTAssertEqual(
            update?.downloadURL.absoluteString,
            "https://github.com/dick86114/MyToken/releases/download/v5.0.0/MyToken-5.0.0-arm64.dmg"
        )
        XCTAssertEqual(update?.notes, "<p>更换品牌名</p>")
        XCTAssertFalse(update?.notes.contains("旧版本日志") == true)
    }

    func testAtom回退在版本化安装包缺失时使用旧固定文件名() async throws {
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/v5.0.0</id>
            <updated>2026-09-03T13:38:39Z</updated>
            <link rel="alternate" href="https://github.com/dick86114/MyToken/releases/tag/v5.0.0" />
            <title>MyToken v5.0.0</title>
          </entry>
        </feed>
        """
        let stub = URLProtocolStub.makeSession { request in
            let url = try XCTUnwrap(request.url)
            if url == GitHubUpdateService.releasesURL {
                let response = try XCTUnwrap(
                    HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)
                )
                return (response, Data())
            }
            if url == GitHubUpdateService.releasesAtomURL {
                let response = try XCTUnwrap(
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                )
                return (response, Data(atom.utf8))
            }
            XCTAssertEqual(request.httpMethod, "HEAD")
            // 只放行旧版固定文件名，验证版本化文件名缺失时逐级回退。
            let statusCode = url.lastPathComponent == "MyToken.dmg" ? 200 : 404
            let response = try XCTUnwrap(
                HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
            )
            return (response, Data())
        }
        let service = GitHubUpdateService(session: stub.session, currentVersion: "1.2.0")

        let update = try await service.checkForUpdate()

        XCTAssertEqual(
            update?.downloadURL.absoluteString,
            "https://github.com/dick86114/MyToken/releases/download/v5.0.0/MyToken.dmg"
        )
    }

    func test下载更新逐步报告百分比并保存完整文件() async throws {
        let payload = Data(repeating: 7, count: 100)
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "100"]
                )
            )
            return (response, payload)
        }
        let service = GitHubUpdateService(session: stub.session, currentVersion: "1.0.0")
        let update = AppUpdate(
            version: "1.1.0",
            releaseURL: URL(string: "https://example.com/release")!,
            downloadURL: URL(string: "https://example.com/MyToken.dmg")!,
            notes: ""
        )
        let progress = DownloadProgressCapture()

        let url = try await service.download(update) { value in
            await progress.append(value)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try Data(contentsOf: url), payload)
        let values = await progress.values
        XCTAssertTrue(values.contains { ($0 ?? 0) > 0 })
        let finalProgress = try XCTUnwrap(values.last ?? nil)
        XCTAssertEqual(finalProgress, 1, accuracy: 0.001)
    }

    func test更新完成标记只会被新进程消费一次() throws {
        let suiteName = "GitHubUpdateServiceTests.notice-(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        UpdateCompletionNotice.record(version: "1.3.0", defaults: defaults)

        XCTAssertEqual(UpdateCompletionNotice.consume(defaults: defaults), "1.3.0")
        XCTAssertNil(UpdateCompletionNotice.consume(defaults: defaults))
    }

    func testCDN模式给下载与发布页地址套镜像前缀() async throws {
        let body = """
        [
          {"tag_name":"macos-v5.2.0","html_url":"https://github.com/dick86114/MyToken/releases/tag/macos-v5.2.0","assets":[{"name":"MyToken-5.2.0-arm64.dmg","browser_download_url":"https://github.com/dick86114/MyToken/releases/download/macos-v5.2.0/MyToken-5.2.0-arm64.dmg"}],"body":""}
        ]
        """
        let stub = URLProtocolStub.makeSession { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data(body.utf8))
        }
        let service = GitHubUpdateService(
            session: stub.session,
            currentVersion: "5.1.0",
            mirrorBaseProvider: { "https://ghfast.top" }
        )

        let update = try await service.checkForUpdate()

        XCTAssertEqual(update?.version, "5.2.0")
        XCTAssertEqual(
            update?.downloadURL.absoluteString,
            "https://ghfast.top/https://github.com/dick86114/MyToken/releases/download/macos-v5.2.0/MyToken-5.2.0-arm64.dmg"
        )
        XCTAssertEqual(
            update?.releaseURL.absoluteString,
            "https://ghfast.top/https://github.com/dick86114/MyToken/releases/tag/macos-v5.2.0"
        )
    }

    func testCDN模式下API不可用时走镜像Atom检测() async throws {
        struct NetworkUnavailable: Error {}
        let atom = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/macos-v5.2.0</id>
            <updated>2026-09-08T08:48:28Z</updated>
            <link rel="alternate" href="https://github.com/dick86114/MyToken/releases/tag/macos-v5.2.0" />
            <title>MyToken v5.2.0</title>
            <content type="html">CDN 检测</content>
          </entry>
        </feed>
        """
        let mirror = "https://ghfast.top"
        let mirroredAtomURL = URL(string: "\(mirror)/\(GitHubUpdateService.releasesAtomURL.absoluteString)")
        let stub = URLProtocolStub.makeSession { request in
            let url = try XCTUnwrap(request.url)
            if url.host == "api.github.com" {
                throw NetworkUnavailable()
            }
            if url == mirroredAtomURL {
                let response = try XCTUnwrap(
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                )
                return (response, Data(atom.utf8))
            }
            let response = try XCTUnwrap(
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data())
        }
        let service = GitHubUpdateService(
            session: stub.session,
            currentVersion: "5.1.0",
            mirrorBaseProvider: { mirror }
        )

        let update = try await service.checkForUpdate()

        XCTAssertEqual(update?.version, "5.2.0")
        XCTAssertTrue(update?.downloadURL.absoluteString.hasPrefix("\(mirror)/https://github.com/") == true)
        XCTAssertTrue(update?.releaseURL.absoluteString.hasPrefix("\(mirror)/https://github.com/") == true)
    }
}

private actor DownloadProgressCapture {
    private(set) var values: [Double?] = []

    func append(_ value: Double?) {
        values.append(value)
    }
}

private actor UpdateLogWriter: AppLogWriting {
    private(set) var events: [String] = []

    func log(level: AppLogLevel, event: String, details: String?) async {
        events.append(event)
    }

    func recentText(maxCharacters: Int) async -> String {
        ""
    }
}

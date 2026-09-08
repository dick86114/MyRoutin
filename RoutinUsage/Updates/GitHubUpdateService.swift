import AppKit
import Foundation

struct AppUpdate: Equatable, Sendable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL
    let notes: String
    let publishedAt: Date?

    init(
        version: String,
        releaseURL: URL,
        downloadURL: URL,
        notes: String,
        publishedAt: Date? = nil
    ) {
        self.version = version
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.notes = notes
        self.publishedAt = publishedAt
    }
}

enum UpdateCompletionNotice {
    private static let versionKey = "updateCompletionVersion"

    static func record(version: String, defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: versionKey)
    }

    static func consume(defaults: UserDefaults = .standard) -> String? {
        let version = defaults.string(forKey: versionKey)
        defaults.removeObject(forKey: versionKey)
        return version
    }
}

enum UpdateServiceError: Error, Equatable, Sendable {
    case unavailable
    case invalidResponse
    case downloadFailed
    case installFailed(String)
}

protocol UpdateChecking: Sendable {
    func checkForUpdate() async throws -> AppUpdate?
    func download(
        _ update: AppUpdate,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws -> URL
}

struct NoUpdateService: UpdateChecking {
    func checkForUpdate() async throws -> AppUpdate? { nil }
    func download(
        _ update: AppUpdate,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws -> URL {
        throw UpdateServiceError.unavailable
    }
}

struct GitHubUpdateService: UpdateChecking, Sendable {
    static let repository = "dick86114/MyToken"
    static let releasesURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100")!
    static let releasesAtomURL = URL(string: "https://github.com/\(repository)/releases.atom")!

    let session: URLSession
    let currentVersion: String
    let logWriter: any AppLogWriting

    init(
        session: URLSession = .shared,
        currentVersion: String? = nil,
        logWriter: any AppLogWriting = NoopAppLogWriter()
    ) {
        self.session = session
        self.currentVersion = currentVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
        self.logWriter = logWriter
    }

    func checkForUpdate() async throws -> AppUpdate? {
        await logWriter.log(
            level: .info,
            event: "update_check_started",
            details: "version=\(currentVersion)"
        )
        var request = URLRequest(
            url: Self.releasesURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MyToken/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            await logWriter.log(level: .warning, event: "update_check_cancelled", details: "source=api")
            throw CancellationError()
        } catch {
            await logWriter.log(
                level: .error,
                event: "update_check_network_failed",
                details: String(describing: error)
            )
            throw UpdateServiceError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            await logWriter.log(level: .error, event: "update_check_invalid_response", details: "source=api")
            throw UpdateServiceError.unavailable
        }
        await logWriter.log(
            level: .info,
            event: "update_check_response",
            details: "source=api status=\(http.statusCode)"
        )
        if http.statusCode == 403 || http.statusCode == 429 {
            // GitHub API 的未登录请求按出口 IP 共享限额，桌面用户很容易撞到 403。
            // Atom feed 不走同一套 API 限额，且足够提供版本和发布页信息。
            await logWriter.log(
                level: .warning,
                event: "update_check_rate_limited",
                details: "status=\(http.statusCode)"
            )
            return try await checkForUpdateFromAtom()
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateServiceError.unavailable
        }
        let release: ReleaseDTO
        do {
            let decoder = JSONDecoder()
            if data.first == 91 { // 兼容历史测试与旧服务返回的单个 Release 对象。
                let releases = try decoder.decode([ReleaseDTO].self, from: data)
                guard let platformRelease = releases.first(where: {
                    $0.tagName.hasPrefix("macos-v")
                }) else {
                    await logWriter.log(level: .info, event: "update_check_succeeded", details: "result=no_macos_release")
                    return nil
                }
                release = platformRelease
            } else {
                release = try decoder.decode(ReleaseDTO.self, from: data)
            }
        } catch {
            await logWriter.log(
                level: .error,
                event: "update_check_decode_failed",
                details: String(describing: error)
            )
            throw UpdateServiceError.invalidResponse
        }
        let version = Self.normalize(release.tagName)
        guard Self.compare(version, currentVersion) == .orderedDescending else {
            await logWriter.log(level: .info, event: "update_check_succeeded", details: "result=no_update")
            return nil
        }
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            await logWriter.log(level: .error, event: "update_check_asset_missing", details: "version=\(version)")
            throw UpdateServiceError.invalidResponse
        }
        guard let releaseURL = URL(string: release.htmlURL) else {
            await logWriter.log(level: .error, event: "update_check_release_url_invalid", details: "version=\(version)")
            throw UpdateServiceError.invalidResponse
        }
        await logWriter.log(level: .info, event: "update_check_succeeded", details: "version=\(version)")
        return AppUpdate(
            version: version,
            releaseURL: releaseURL,
            downloadURL: downloadURL,
            notes: release.body ?? "",
            publishedAt: Self.parseISO8601(release.publishedAt)
        )
    }

    private func checkForUpdateFromAtom() async throws -> AppUpdate? {
        await logWriter.log(level: .info, event: "update_check_atom_started", details: nil)
        var request = URLRequest(
            url: Self.releasesAtomURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        request.setValue("MyToken/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            await logWriter.log(level: .warning, event: "update_check_cancelled", details: "source=atom")
            throw CancellationError()
        } catch {
            await logWriter.log(
                level: .error,
                event: "update_check_atom_network_failed",
                details: String(describing: error)
            )
            throw UpdateServiceError.unavailable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            await logWriter.log(level: .error, event: "update_check_atom_failed", details: "response=invalid")
            throw UpdateServiceError.unavailable
        }
        await logWriter.log(
            level: .info,
            event: "update_check_response",
            details: "source=atom status=\(http.statusCode)"
        )

        let parser = AtomReleaseParser()
        guard let release = parser.parse(data: data) else {
            await logWriter.log(level: .error, event: "update_check_atom_decode_failed", details: nil)
            throw UpdateServiceError.invalidResponse
        }
        let version = Self.normalize(release.version)
        guard Self.compare(version, currentVersion) == .orderedDescending else {
            await logWriter.log(level: .info, event: "update_check_succeeded", details: "result=no_update source=atom")
            return nil
        }

        let tag = release.version.hasPrefix("macos-") ? release.version : "v\(version)"
        guard let assetName = try await Self.resolveDMGAssetName(version: version, tag: tag, session: session),
              let downloadURL = URL(
                string: "https://github.com/\(Self.repository)/releases/download/\(tag)/\(assetName)"
              ),
              let releaseURL = URL(string: release.releaseURL) else {
            await logWriter.log(
                level: .error,
                event: "update_check_atom_asset_missing",
                details: "version=\(version)"
            )
            throw UpdateServiceError.invalidResponse
        }
        await logWriter.log(
            level: .info,
            event: "update_check_succeeded",
            details: "version=\(version) source=atom"
        )
        return AppUpdate(
            version: version,
            releaseURL: releaseURL,
            downloadURL: downloadURL,
            notes: release.notes,
            publishedAt: release.publishedAt
        )
    }

    /// Atom feed 不包含资产列表，只能按命名约定探测下载地址：
    /// 优先新命名的版本化文件（GitHub macOS CI runner 为 arm64），再回退旧的固定文件名。
    private static func resolveDMGAssetName(
        version: String,
        tag: String,
        session: URLSession
    ) async throws -> String? {
        let baseURL = "https://github.com/\(repository)/releases/download/\(tag)"
        let candidates = [
            "MyToken-\(version)-arm64.dmg",
            "MyToken-\(version)-x86_64.dmg",
            "MyToken.dmg",
        ]
        for candidate in candidates {
            guard let url = URL(string: "\(baseURL)/\(candidate)") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "HEAD"
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    return candidate
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return nil
    }

    func download(
        _ update: AppUpdate,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws -> URL {
        await logWriter.log(
            level: .info,
            event: "update_download_started",
            details: "version=\(update.version)"
        )
        do {
            let (bytes, response) = try await session.bytes(from: update.downloadURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                await logWriter.log(
                    level: .error,
                    event: "update_download_failed",
                    details: "version=\(update.version) response=invalid"
                )
                throw UpdateServiceError.downloadFailed
            }

            let totalBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            var data = Data()
            if let totalBytes {
                data.reserveCapacity(Int(totalBytes))
            }
            var receivedBytes: Int64 = 0
            var lastReportedProgress = -1.0

            for try await byte in bytes {
                data.append(byte)
                receivedBytes += 1
                guard let totalBytes else {
                    if receivedBytes == 1 {
                        await progress(nil)
                    }
                    continue
                }
                let currentProgress = min(max(Double(receivedBytes) / Double(totalBytes), 0), 1)
                if currentProgress - lastReportedProgress >= 0.01 || currentProgress >= 1 {
                    lastReportedProgress = currentProgress
                    await progress(currentProgress)
                }
            }

            guard !data.isEmpty else {
                await logWriter.log(
                    level: .error,
                    event: "update_download_failed",
                    details: "version=\(update.version) response=empty"
                )
                throw UpdateServiceError.downloadFailed
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyToken-\(update.version).dmg")
            try data.write(to: url, options: .atomic)
            await logWriter.log(
                level: .info,
                event: "update_download_succeeded",
                details: "version=\(update.version) bytes=\(data.count)"
            )
            return url
        } catch is CancellationError {
            await logWriter.log(level: .warning, event: "update_download_cancelled", details: "version=\(update.version)")
            throw CancellationError()
        } catch let error as UpdateServiceError {
            await logWriter.log(
                level: .error,
                event: "update_download_failed",
                details: "version=\(update.version) error=\(String(describing: error))"
            )
            throw error
        } catch {
            await logWriter.log(
                level: .error,
                event: "update_download_failed",
                details: "version=\(update.version) error=\(String(describing: error))"
            )
            throw UpdateServiceError.downloadFailed
        }
    }

    private struct ReleaseDTO: Decodable {
        let tagName: String
        let htmlURL: String
        let body: String?
        let publishedAt: String?
        let assets: [AssetDTO]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case publishedAt = "published_at"
            case assets
        }
    }
    private struct AssetDTO: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey { case name, browserDownloadURL = "browser_download_url" }
    }
    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^(macos-|android-)?v", with: "", options: .regularExpression)
    }
    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(a.count, b.count) {
            let av = index < a.count ? a[index] : 0; let bv = index < b.count ? b[index] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct AtomRelease {
    let version: String
    let releaseURL: String
    let notes: String
    let publishedAt: Date?
}

private final class AtomReleaseParser: NSObject, XMLParserDelegate {
    private var currentText = ""
    private var inEntry = false
    private var version: String?
    private var releaseURL: String?
    private var publishedText: String?
    private var notes = ""
    private var stoppedAfterFirstEntry = false
    func parse(data: Data) -> AtomRelease? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        // Atom Feed 按最新版本排序。解析完第一条后停止，避免旧版本字段覆盖新版本。
        _ = parser.parse()
        guard stoppedAfterFirstEntry, let version, let releaseURL else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return AtomRelease(
            version: version,
            releaseURL: releaseURL,
            notes: notes,
            publishedAt: publishedText.flatMap(formatter.date(from:))
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !inEntry else {
            currentText = ""
            if elementName == "link", attributeDict["rel"] == "alternate" {
                releaseURL = attributeDict["href"]
            }
            return
        }
        if elementName == "entry" {
            inEntry = true
            currentText = ""
            version = nil
            releaseURL = nil
            publishedText = nil
            notes = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard inEntry else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "id" where version == nil:
            version = text.split(separator: "/").last.map(String.init)
        case "title":
            if version == nil {
                version = text.split(whereSeparator: { $0 == "v" || $0 == " " }).last.map(String.init)
            }
        case "content":
            notes = text
        case "published", "updated":
            if publishedText == nil {
                publishedText = text
            }
        case "entry":
            inEntry = false
            let isMacOSRelease = version?.range(of: "^(macos-)?v[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil
            if isMacOSRelease {
                stoppedAfterFirstEntry = true
                parser.abortParsing()
            }
        default:
            break
        }
        currentText = ""
    }
}

@MainActor
enum UpdateInstaller {
    static func install(
        dmgURL: URL,
        appName: String = "MyToken",
        version: String,
        logWriter: any AppLogWriting = AppLogStore.shared
    ) throws {
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("routin-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
            try? FileManager.default.removeItem(at: mountPoint)
        }
        guard run("/usr/bin/hdiutil", ["attach", dmgURL.path, "-nobrowse", "-mountpoint", mountPoint.path]) == 0 else {
            throw UpdateServiceError.installFailed("无法挂载更新磁盘映像")
        }
        let source = mountPoint.appendingPathComponent("\(appName).app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw UpdateServiceError.installFailed("更新包中未找到应用") }
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent("\(appName).app")
        let temporaryDestination = destination.deletingLastPathComponent().appendingPathComponent(".\(appName)-new.app")
        try? FileManager.default.removeItem(at: temporaryDestination)
        guard run("/usr/bin/ditto", [source.path, temporaryDestination.path]) == 0 else { throw UpdateServiceError.installFailed("复制新版本失败") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryDestination, to: destination)
        UpdateCompletionNotice.record(version: version)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            Task { @MainActor in
                if error == nil {
                    await logWriter.log(level: .info, event: "update_restart_succeeded", details: "version=\(version)")
                    NSApplication.shared.terminate(nil)
                    return
                }

                await logWriter.log(
                    level: .error,
                    event: "update_restart_failed",
                    details: String(describing: error)
                )

                // 新版本已复制完成但系统拒绝自动启动时，保留旧进程并给出可操作提示。
                let alert = NSAlert()
                alert.messageText = "更新已安装"
                alert.informativeText = "新版本已安装到“应用程序”文件夹，请手动重新打开 MyToken。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus } catch { return -1 }
    }
}

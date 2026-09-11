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

struct AppReleaseHistoryItem: Identifiable, Equatable, Sendable {
    let version: String
    let releaseURL: URL
    let notes: String
    let publishedAt: Date?

    var id: String { version }
}

enum AppReleaseHistoryState: Equatable, Sendable {
    case idle
    case loading
    case loaded([AppReleaseHistoryItem])
    case failed(String)
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
    func fetchReleaseHistory() async throws -> [AppReleaseHistoryItem]
    func download(
        _ update: AppUpdate,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws -> URL
}


struct NoUpdateService: UpdateChecking {
    func checkForUpdate() async throws -> AppUpdate? { nil }
    func fetchReleaseHistory() async throws -> [AppReleaseHistoryItem] { [] }
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
    static let releasesPageURL = URL(string: "https://github.com/\(repository)/releases")!
    static let releasesAtomURL = URL(string: "https://github.com/\(repository)/releases.atom")!

    let session: URLSession
    let currentVersion: String
    let logWriter: any AppLogWriting
    /// 返回当前镜像前缀（如 `https://ghfast.top`）；nil 表示 GitHub 直连。
    let mirrorBaseProvider: @Sendable () -> String?

    init(
        session: URLSession = .shared,
        currentVersion: String? = nil,
        logWriter: any AppLogWriting = NoopAppLogWriter(),
        mirrorBaseProvider: @escaping @Sendable () -> String? = {
            UserDefaults.standard.string(forKey: "updateMirrorBase")
        }
    ) {
        self.session = session
        self.currentVersion = currentVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
        self.logWriter = logWriter
        self.mirrorBaseProvider = mirrorBaseProvider
    }

    /// CDN 模式下把 `https://github.com/...` 地址套上镜像前缀；其余地址原样返回。
    private func rewritten(_ url: URL, mirror: String?) -> URL {
        guard let mirror,
              !mirror.isEmpty,
              url.scheme == "https",
              url.host == "github.com" else {
            return url
        }
        return URL(string: "\(mirror)/\(url.absoluteString)") ?? url
    }

    private func rewrittenString(_ value: String, mirror: String?) -> String {
        guard let url = URL(string: value) else { return value }
        return rewritten(url, mirror: mirror).absoluteString
    }

    private static func releasesURL(page: Int) -> URL {
        guard page > 1,
              var components = URLComponents(url: releasesURL, resolvingAgainstBaseURL: false) else {
            return releasesURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
        components.queryItems = queryItems
        return components.url ?? releasesURL
    }

    private static func releasesPageURL(page: Int) -> URL {
        guard page > 1,
              var components = URLComponents(url: releasesPageURL, resolvingAgainstBaseURL: false) else {
            return releasesPageURL
        }
        components.queryItems = [URLQueryItem(name: "page", value: "\(page)")]
        return components.url ?? releasesPageURL
    }

    func checkForUpdate() async throws -> AppUpdate? {
        await logWriter.log(
            level: .info,
            event: "update_check_started",
            details: "version=\(currentVersion) mirror=\(mirrorBaseProvider() ?? "direct")"
        )
        let mirror = mirrorBaseProvider()
        let releases: [ReleaseDTO]
        do {
            releases = try await fetchReleases(mirror: mirror)
        } catch {
            // GitHub API 可能限流，Atom 源无论是否启用镜像都应作为回退路径。
            return try await checkForUpdateFromAtom(mirror: mirror)
        }
        let macOSReleases = releases
            .filter { Self.isMacOSRelease(tagName: $0.tagName) }
        let release = macOSReleases
            .filter { $0.assets.contains { $0.name.hasSuffix(".dmg") } }
            .max(by: {
                Self.compare(Self.normalize($0.tagName), Self.normalize($1.tagName)) == .orderedAscending
            })
        guard let release else {
            await logWriter.log(level: .info, event: "update_check_succeeded", details: "result=no_macos_release")
            return nil
        }
        let version = Self.normalize(release.tagName)
        guard Self.compare(version, currentVersion) == .orderedDescending else {
            await logWriter.log(level: .info, event: "update_check_succeeded", details: "result=no_update")
            return nil
        }
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let downloadURL = URL(string: rewrittenString(asset.browserDownloadURL, mirror: mirror)) else {
            await logWriter.log(level: .error, event: "update_check_asset_missing", details: "version=\(version)")
            throw UpdateServiceError.invalidResponse
        }
        guard let releaseURL = URL(string: rewrittenString(release.htmlURL ?? "", mirror: mirror)) else {
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

    func fetchReleaseHistory() async throws -> [AppReleaseHistoryItem] {
        let mirror = mirrorBaseProvider()
        await logWriter.log(
            level: .info,
            event: "release_history_started",
            details: "version=\(currentVersion) mirror=\(mirror ?? "direct")"
        )
        let releases: [ReleaseDTO]
        do {
            releases = try await fetchAllReleases(mirror: mirror)
        } catch {
            await logWriter.log(level: .warning, event: "release_history_html_fallback", details: nil)
            do {
                let history = try await fetchReleaseHistoryFromHTML(mirror: mirror)
                if !history.isEmpty {
                    return history
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                await logWriter.log(
                    level: .warning,
                    event: "release_history_html_failed",
                    details: String(describing: error)
                )
            }
            await logWriter.log(level: .warning, event: "release_history_atom_fallback", details: nil)
            return try await fetchReleaseHistoryFromAtom(mirror: mirror)
        }
        var seen = Set<String>()
        let history = releases
            .filter { Self.isMacOSRelease(tagName: $0.tagName) }
            .compactMap { release -> AppReleaseHistoryItem? in
                let version = Self.normalize(release.tagName)
                guard !version.isEmpty, seen.insert(version).inserted,
                      let releaseURL = URL(string: rewrittenString(release.htmlURL ?? "", mirror: mirror)) else {
                    return nil
                }
                return AppReleaseHistoryItem(
                    version: version,
                    releaseURL: releaseURL,
                    notes: release.body ?? "",
                    publishedAt: Self.parseISO8601(release.publishedAt)
                )
            }
            .sorted {
                Self.compare($0.version, $1.version) == .orderedDescending
            }
        await logWriter.log(
            level: .info,
            event: "release_history_loaded",
            details: "source=api count=\(history.count) first=\(history.first?.version ?? "none")"
        )
        return history
    }

    private func fetchAllReleases(mirror: String?) async throws -> [ReleaseDTO] {
        var allReleases: [ReleaseDTO] = []
        var page = 1
        while page <= 50 {
            let releases = try await fetchReleases(mirror: mirror, page: page)
            allReleases.append(contentsOf: releases)
            guard releases.count == 100 else { break }
            page += 1
        }
        return allReleases
    }

    private func fetchReleases(mirror: String?, page: Int = 1) async throws -> [ReleaseDTO] {
        var request = URLRequest(
            url: Self.releasesURL(page: page),
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
            await logWriter.log(
                level: .warning,
                event: "update_check_rate_limited",
                details: "status=\(http.statusCode)"
            )
            throw UpdateServiceError.unavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateServiceError.unavailable
        }
        do {
            if data.first == 91 {
                return try JSONDecoder().decode([ReleaseDTO].self, from: data)
            }
            return [try JSONDecoder().decode(ReleaseDTO.self, from: data)]
        } catch {
            await logWriter.log(
                level: .error,
                event: "update_check_decode_failed",
                details: String(describing: error)
            )
            throw UpdateServiceError.invalidResponse
        }
    }

    private func checkForUpdateFromAtom(mirror: String?) async throws -> AppUpdate? {
        let releases = try await fetchAtomReleases(mirror: mirror)
        guard let release = releases.first(where: { Self.isMacOSRelease(tagName: $0.version) }) else {
            await logWriter.log(level: .error, event: "update_check_atom_decode_failed", details: nil)
            throw UpdateServiceError.invalidResponse
        }
        let version = Self.normalize(release.version)
        guard Self.compare(version, currentVersion) == .orderedDescending else {
            await logWriter.log(level: .info, event: "update_check_succeeded", details: "result=no_update source=atom")
            return nil
        }

        let tag = release.version.hasPrefix("macos-") ? release.version : "v\(version)"
        guard let assetName = try await Self.resolveDMGAssetName(
                version: version,
                tag: tag,
                session: session,
                mirror: mirror
              ),
              let downloadURL = URL(
                string: rewrittenString(
                  "https://github.com/\(Self.repository)/releases/download/\(tag)/\(assetName)",
                  mirror: mirror
                )
              ),
              let releaseURL = URL(string: rewrittenString(release.releaseURL, mirror: mirror)) else {
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

    /// GitHub Releases HTML 仍有分页；Atom 只给最近 10 条，不能作为完整历史来源。
    private func fetchReleaseHistoryFromHTML(mirror: String?) async throws -> [AppReleaseHistoryItem] {
        var page = 1
        var parsedReleases: [HTMLRelease] = []
        while page <= 50 {
            let url = rewritten(Self.releasesPageURL(page: page), mirror: mirror)
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("MyToken/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw UpdateServiceError.unavailable
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                throw UpdateServiceError.unavailable
            }

            let releases = Self.parseReleaseHistoryHTML(html)
            if page > 1, releases.isEmpty { break }
            parsedReleases.append(contentsOf: releases)
            guard html.contains("rel=\"next\"") else { break }
            page += 1
        }
        guard !parsedReleases.isEmpty else { throw UpdateServiceError.invalidResponse }

        var seen = Set<String>()
        let history = parsedReleases
            .filter { Self.isMacOSRelease(tagName: $0.tagName) }
            .compactMap { release -> AppReleaseHistoryItem? in
                let version = Self.normalize(release.tagName)
                guard !version.isEmpty, seen.insert(version).inserted,
                      let releaseURL = URL(string: rewrittenString(
                        "https://github.com/\(Self.repository)/releases/tag/\(release.tagName)",
                        mirror: mirror
                      )) else {
                    return nil
                }
                return AppReleaseHistoryItem(
                    version: version,
                    releaseURL: releaseURL,
                    notes: release.notesHTML,
                    publishedAt: Self.parseISO8601(release.publishedAt)
                )
            }
            .sorted {
                Self.compare($0.version, $1.version) == .orderedDescending
            }
        await logWriter.log(
            level: .info,
            event: "release_history_loaded",
            details: "source=html count=\(history.count) first=\(history.first?.version ?? "none")"
        )
        return history
    }

    private static func parseReleaseHistoryHTML(_ html: String) -> [HTMLRelease] {
        let pattern = "<section id=\"release-([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
        return matches.enumerated().compactMap { index, match in
            guard match.numberOfRanges > 1 else { return nil }
            let tagName = source.substring(with: match.range(at: 1))
            let blockStart = match.range.location
            let blockEnd = index + 1 < matches.count ? matches[index + 1].range.location : source.length
            let block = source.substring(with: NSRange(location: blockStart, length: blockEnd - blockStart))
            let publishedAt = firstMatch(pattern: "datetime=\"([^\"]+)\"", in: block)
            let notesHTML = extractDivInnerHTML(
                containing: "data-test-selector=\"body-content\"",
                in: block
            ) ?? ""
            return HTMLRelease(tagName: tagName, notesHTML: notesHTML, publishedAt: publishedAt)
        }
    }

    private static func firstMatch(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = value as NSString
        guard let match = regex.firstMatch(
            in: value,
            range: NSRange(location: 0, length: source.length)
        ), match.numberOfRanges > 1 else { return nil }
        return source.substring(with: match.range(at: 1))
    }

    private static func extractDivInnerHTML(containing marker: String, in value: String) -> String? {
        guard let markerRange = value.range(of: marker),
              let openingEnd = value[markerRange.upperBound...].firstIndex(of: ">") else {
            return nil
        }
        let contentStart = value.index(after: openingEnd)
        guard let regex = try? NSRegularExpression(
            pattern: "</?div\\b[^>]*>",
            options: [.caseInsensitive]
        ) else { return nil }
        let searchRange = NSRange(contentStart..<value.endIndex, in: value)
        var depth = 0
        for match in regex.matches(in: value, range: searchRange) {
            guard let range = Range(match.range, in: value) else { continue }
            let token = String(value[range])
            if token.hasPrefix("</") {
                if depth == 0 {
                    return String(value[contentStart..<range.lowerBound])
                }
                depth -= 1
            } else if !token.hasSuffix("/>") {
                depth += 1
            }
        }
        return nil
    }

    private func fetchReleaseHistoryFromAtom(mirror: String?) async throws -> [AppReleaseHistoryItem] {
        let releases = try await fetchAtomReleases(mirror: mirror)
        await logWriter.log(
            level: .info,
            event: "release_history_atom_parsed",
            details: "count=\(releases.count) first=\(releases.first?.version ?? "none")"
        )
        var seen = Set<String>()
        let history = releases
            .compactMap { release -> AppReleaseHistoryItem? in
                guard Self.isMacOSRelease(tagName: release.version) else { return nil }
                let version = Self.normalize(release.version)
                guard !version.isEmpty, seen.insert(version).inserted,
                      let releaseURL = URL(string: rewrittenString(release.releaseURL, mirror: mirror)) else {
                    return nil
                }
                return AppReleaseHistoryItem(
                    version: version,
                    releaseURL: releaseURL,
                    notes: release.notes,
                    publishedAt: release.publishedAt
                )
            }
            .sorted {
                Self.compare($0.version, $1.version) == .orderedDescending
            }
        await logWriter.log(
            level: .info,
            event: "release_history_loaded",
            details: "source=atom count=\(history.count) first=\(history.first?.version ?? "none")"
        )
        return history
    }

    private func fetchAtomReleases(mirror: String?) async throws -> [AtomRelease] {
        await logWriter.log(level: .info, event: "update_check_atom_started", details: nil)
        var request = URLRequest(
            url: rewritten(Self.releasesAtomURL, mirror: mirror),
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

        let releases = AtomReleaseParser().parseAll(data: data)
        guard !releases.isEmpty else {
            await logWriter.log(level: .error, event: "update_check_atom_decode_failed", details: nil)
            throw UpdateServiceError.invalidResponse
        }
        return releases
    }

    private static func resolveDMGAssetName(
        version: String,
        tag: String,
        session: URLSession,
        mirror: String?
    ) async throws -> String? {
        let baseURL = "https://github.com/\(repository)/releases/download/\(tag)"
        let candidates = [
            "MyToken-\(version)-arm64.dmg",
            "MyToken-\(version)-x86_64.dmg",
            "MyToken.dmg",
        ]
        for candidate in candidates {
            guard let url = URL(string: "\(baseURL)/\(candidate)") else { continue }
            var request = URLRequest(
                url: {
                    guard let mirror, url.host == "github.com" else { return url }
                    return URL(string: "\(mirror)/\(url.absoluteString)") ?? url
                }(),
                timeoutInterval: 30
            )
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
        let mirror = mirrorBaseProvider()
        let downloadURL = rewritten(update.downloadURL, mirror: mirror)
        await logWriter.log(
            level: .info,
            event: "update_download_started",
            details: "version=\(update.version) mirror=\(mirror ?? "direct")"
        )
        do {
            let (bytes, response) = try await session.bytes(from: downloadURL)
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
        let htmlURL: String?
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

    /// 主发布（vX.Y.Z）与平台发布（macos-vX.Y.Z）都算 macOS 更新候选。
    static func isMacOSRelease(tagName: String) -> Bool {
        tagName.range(of: "^(macos-)?v[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil
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

private struct HTMLRelease {
    let tagName: String
    let notesHTML: String
    let publishedAt: String?
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
    private var releases: [AtomRelease] = []

    func parseAll(data: Data) -> [AtomRelease] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return releases
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
            if let version, let releaseURL {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                releases.append(
                    AtomRelease(
                        version: version,
                        releaseURL: releaseURL,
                        notes: notes,
                        publishedAt: publishedText.flatMap(formatter.date(from:))
                    )
                )
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

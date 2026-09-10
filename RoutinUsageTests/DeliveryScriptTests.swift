import Foundation
import XCTest

final class DeliveryScriptTests: XCTestCase {
    func test构建脚本已打包为测试资源() {
        XCTAssertNotNil(
            Bundle(for: DeliveryScriptTests.self)
                .url(forResource: "build-dmg", withExtension: "sh")
        )
    }

    func testXcode校验脚本接受Xcode26与macOS26SDK() throws {
        let result = try runXcodeVerification(
            xcodeVersion: "Xcode 26.6\nBuild version 17F113",
            sdkVersion: "26.6"
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Xcode 26.6"), result.output)
        XCTAssertTrue(result.output.contains("macOS SDK 26.6"), result.output)
    }

    func testXcode校验脚本接受Xcode27与macOS27SDK() throws {
        let result = try runXcodeVerification(
            xcodeVersion: "Xcode 27.0\nBuild version 18A100",
            sdkVersion: "27.0"
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Xcode 27.0"), result.output)
        XCTAssertTrue(result.output.contains("macOS SDK 27.0"), result.output)
    }

    func testXcode校验脚本拒绝旧版Xcode() throws {
        let result = try runXcodeVerification(
            xcodeVersion: "Xcode 16.4\nBuild version 16F6",
            sdkVersion: "15.5"
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("需要 Xcode 26 或更高版本"), result.output)
    }

    func test测试脚本将偏好设置隔离至临时目录() throws {
        let script = try XCTUnwrap(
            Bundle(for: DeliveryScriptTests.self)
                .url(forResource: "test", withExtension: "sh")
        )
        let source = try String(contentsOf: script, encoding: .utf8)

        XCTAssertTrue(source.contains("CFFIXED_USER_HOME"))
        XCTAssertTrue(source.contains("mktemp -d"))
        XCTAssertTrue(source.contains("trap cleanup_test_home EXIT"))
        XCTAssertTrue(source.contains("cleanup_test_preferences"))
        XCTAssertTrue(source.contains("sleep 10"))
        XCTAssertTrue(source.contains("ai.routin.usage-monitor.*-tests.*.plist"))
        XCTAssertTrue(source.contains("AppSettingsTests.*.plist"))
        XCTAssertTrue(source.contains("AppLifecycleTests.*.plist"))
    }

    func test构建脚本从仓库外调用仍固定使用脚本所在仓库() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runScript(fixture.script, currentDirectory: fixture.outside)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("仓库根目录：")
                && result.output.contains("/temporary-repository"),
            result.output
        )
        XCTAssertTrue(
            result.output.contains("/temporary-repository/build/dist"),
            result.output
        )
        XCTAssertFalse(result.output.contains(fixture.outside.appendingPathComponent("build").path))
    }

    func test构建目录为外指符号链接时拒绝清理且保留外部文件() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let externalBuild = fixture.outside.appendingPathComponent("external-build")
        try FileManager.default.createDirectory(
            at: externalBuild,
            withIntermediateDirectories: true
        )
        let sentinel = externalBuild.appendingPathComponent("不可删除.txt")
        try Data("保留".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: fixture.repository.appendingPathComponent("build"),
            withDestinationURL: externalBuild
        )

        let result = try runScript(fixture.script, currentDirectory: fixture.outside)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("build 不能是符号链接"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    private func makeFixture() throws -> ScriptFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutinUsage-DeliveryScriptTests-\(UUID().uuidString)")
        let repository = root.appendingPathComponent("temporary-repository")
        let scripts = repository.appendingPathComponent("scripts")
        let outside = root.appendingPathComponent("outside-working-directory")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("name: Fixture\n".utf8).write(
            to: repository.appendingPathComponent("project.yml")
        )

        guard let sourceScript = Bundle(for: DeliveryScriptTests.self)
            .url(forResource: "build-dmg", withExtension: "sh")
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        let copiedScript = scripts.appendingPathComponent("build-dmg.sh")
        try FileManager.default.copyItem(at: sourceScript, to: copiedScript)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: copiedScript.path
        )
        return ScriptFixture(
            root: root,
            repository: repository,
            outside: outside,
            script: copiedScript
        )
    }

    private func runScript(
        _ script: URL,
        currentDirectory: URL
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["ROUTIN_DMG_DRY_RUN"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func runXcodeVerification(
        xcodeVersion: String,
        sdkVersion: String
    ) throws -> (status: Int32, output: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutinUsage-XcodeVerificationTests-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try makeExecutable(
            at: bin.appendingPathComponent("xcodebuild"),
            contents: "#!/bin/bash\nprintf '%s\\n' \(shellQuoted(xcodeVersion))\n"
        )
        try makeExecutable(
            at: bin.appendingPathComponent("xcrun"),
            contents: "#!/bin/bash\nprintf '%s\\n' \(shellQuoted(sdkVersion))\n"
        )
        let script = try XCTUnwrap(
            Bundle(for: DeliveryScriptTests.self)
                .url(forResource: "verify-xcode", withExtension: "sh")
        )
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(bin.path):/usr/bin:/bin"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func makeExecutable(at url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct ScriptFixture {
    let root: URL
    let repository: URL
    let outside: URL
    let script: URL
}

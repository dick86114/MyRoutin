import XCTest
@testable import RoutinUsage

final class ModelIDChipFlowTests: XCTestCase {
    func test同一模型ID生成稳定配色索引() {
        let first = ModelIDChipPalette.colorIndex(for: "doubao-seed-2-1-turbo")
        let second = ModelIDChipPalette.colorIndex(for: "doubao-seed-2-1-turbo")

        XCTAssertEqual(first, second)
        XCTAssertTrue(first >= 0)
        XCTAssertTrue(first < ModelIDChipPalette.colorCount)
    }

    func test不同模型ID使用多种配色索引() {
        let values = [
            "ark-code-latest",
            "doubao-seed-2-0-lite",
            "glm-5.3",
            "kimi-k2.7-code",
            "deepseek-v4-pro"
        ].map(ModelIDChipPalette.colorIndex(for:))

        XCTAssertEqual(Set(values).count, values.count)
    }
}

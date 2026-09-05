import XCTest
@testable import RoutinUsage

final class CredentialDisplayOrderTests: XCTestCase {
    private let one = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let two = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let three = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let four = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private let five = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

    private var order: CredentialDisplayOrder {
        CredentialDisplayOrder(
            menuBarCredentialIDs: [two, one],
            popoverCredentialIDs: [two, three, one, four]
        )
    }

    func test可见序列过滤停用凭证并派生菜单栏待选区() {
        let visibility = order.visible(enabledIDs: [one, two, four])

        XCTAssertEqual(visibility.menuBarIDs, [two, one])
        XCTAssertEqual(visibility.popoverIDs, [two, one, four])
        XCTAssertEqual(visibility.menuBarCandidateIDs, [four])
    }

    func test菜单栏排序不影响弹窗排序() {
        let result = order.moving(.menuBar, id: one, toIndex: 0)

        XCTAssertEqual(result.menuBarCredentialIDs, [one, two])
        XCTAssertEqual(result.popoverCredentialIDs, order.popoverCredentialIDs)
    }

    func test弹窗排序不影响菜单栏排序() {
        let result = order.moving(.popover, id: four, toIndex: 0)

        XCTAssertEqual(result.menuBarCredentialIDs, order.menuBarCredentialIDs)
        XCTAssertEqual(result.popoverCredentialIDs, [four, two, three, one])
    }

    func test统一列表拖拽到菜单栏卡片会加入并按统一顺序重排() {
        let result = order.movingDisplay(id: four, before: two)

        XCTAssertEqual(result.popoverCredentialIDs, [four, two, three, one])
        XCTAssertEqual(result.menuBarCredentialIDs, [four, two, one])
    }

    func test统一列表拖拽到待选卡片会移出菜单栏() {
        let result = order.movingDisplay(id: one, before: four)

        XCTAssertEqual(result.popoverCredentialIDs, [two, three, one, four])
        XCTAssertEqual(result.menuBarCredentialIDs, [two])
    }

    func test弹窗序列第一项移动到第二格会真正换位() {
        let result = order.moving(.popover, id: two, toIndex: 1)

        XCTAssertEqual(result.popoverCredentialIDs, [three, two, one, four])
        XCTAssertEqual(result.menuBarCredentialIDs, [two, one])
    }

    func test菜单栏已满时待选卡片不能拖入() {
        let base = CredentialDisplayOrder(
            menuBarCredentialIDs: [one, two, three, four, five],
            popoverCredentialIDs: [one, two, three, four, five]
        )
        let candidate = UUID()
        var full = base
        full.popoverCredentialIDs = base.popoverCredentialIDs + [candidate]

        let rejected = full.movingDisplay(id: candidate, before: three)

        XCTAssertEqual(rejected, full)
    }

    func test待选凭证加入菜单栏且上限为五() {
        let base = CredentialDisplayOrder(
            menuBarCredentialIDs: [one, two, three, four, five],
            popoverCredentialIDs: [one, two, three, four, five]
        )
        let candidate = UUID()
        let rejected = base.addingToMenuBar(candidate, toIndex: 0)
        XCTAssertEqual(rejected, base)

        let removable = base.removingFromMenuBar(four)
        let accepted = removable.addingToMenuBar(candidate, toIndex: 0)
        XCTAssertEqual(accepted.menuBarCredentialIDs, [candidate, one, two, three, five])
        XCTAssertEqual(accepted.popoverCredentialIDs, base.popoverCredentialIDs)
    }

    func test删除凭证同步清理两个独立序列() {
        let result = order.removingCredential(one)

        XCTAssertEqual(result.menuBarCredentialIDs, [two])
        XCTAssertEqual(result.popoverCredentialIDs, [two, three, four])
    }

    func test旧配置迁移保留菜单栏和弹窗稳定顺序() {
        let disabled = UUID()
        let result = CredentialDisplayOrder.migrated(
            selected: [two, one],
            available: [three],
            allIDs: [one, two, three, disabled]
        )

        XCTAssertEqual(result.menuBarCredentialIDs, [two, one])
        XCTAssertEqual(result.popoverCredentialIDs, [two, one, three, disabled])
    }

    func test构造时去重并将菜单栏截断到前五项() {
        let candidate = UUID()
        let result = CredentialDisplayOrder(
            menuBarCredentialIDs: [candidate, one, two, three, four, five],
            popoverCredentialIDs: [three, three, two, one]
        )

        XCTAssertEqual(result.menuBarCredentialIDs, [candidate, one, two, three, four])
        XCTAssertEqual(result.popoverCredentialIDs, [three, two, one])
    }

    func test解码时去重并将菜单栏截断到前五项() throws {
        let candidate = UUID().uuidString
        let json = """
        {
          "menuBarCredentialIDs": [
            "\(candidate)", "\(one.uuidString)", "\(two.uuidString)",
            "\(candidate)", "\(three.uuidString)", "\(four.uuidString)",
            "\(five.uuidString)", "\(two.uuidString)"
          ],
          "popoverCredentialIDs": [
            "\(three.uuidString)", "\(three.uuidString)", "\(candidate)",
            "\(one.uuidString)", "\(five.uuidString)"
          ]
        }
        """

        let result = try JSONDecoder().decode(CredentialDisplayOrder.self, from: Data(json.utf8))

        XCTAssertEqual(
            result.menuBarCredentialIDs,
            [UUID(uuidString: candidate)!, one, two, three, four]
        )
        XCTAssertEqual(result.popoverCredentialIDs, [three, UUID(uuidString: candidate)!, one, five])
    }

    func test直接修改属性时保持去重和菜单栏上限() {
        var result = CredentialDisplayOrder(
            menuBarCredentialIDs: [one],
            popoverCredentialIDs: [one]
        )

        result.menuBarCredentialIDs = [one, one, two, three, four, five, two]
        XCTAssertEqual(result.menuBarCredentialIDs, [one, two, three, four, five])

        result.popoverCredentialIDs = [one, one, five, five, three]
        XCTAssertEqual(result.popoverCredentialIDs, [one, five, three])
    }
}

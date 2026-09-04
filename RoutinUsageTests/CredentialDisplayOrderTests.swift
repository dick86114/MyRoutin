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
}

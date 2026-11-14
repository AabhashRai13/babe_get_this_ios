import XCTest
@testable import BabeGetThis

/// The join dialog's field (Android `JoinListDialog`, SHARE-04). The open / join / error flow
/// itself lives in `ListsViewModel` and is covered by `ShoppingListViewModelTests`.
@MainActor
final class JoinListViewModelTests: XCTestCase {
    func testJoinEnabledOnlyAtSixChars() {
        let vm = JoinListViewModel()
        XCTAssertFalse(vm.isJoinEnabled(isJoining: false))

        vm.updateCode("ABC23")
        XCTAssertFalse(vm.isJoinEnabled(isJoining: false))

        vm.updateCode("ABC234")
        XCTAssertTrue(vm.isJoinEnabled(isJoining: false))
    }

    func testJoinIsDisabledWhileAJoinIsRunning() {
        let vm = JoinListViewModel()
        vm.updateCode("ABC234")

        XCTAssertFalse(vm.isJoinEnabled(isJoining: true))
    }

    func testInputIsTrimmed() {
        let vm = JoinListViewModel()

        vm.updateCode("  ABC234 \n")

        XCTAssertEqual(vm.code, "ABC234")
    }

    func testInputIsUppercased() {
        let vm = JoinListViewModel()

        vm.updateCode("abc234")

        XCTAssertEqual(vm.code, "ABC234")
    }

    func testInputIsCappedAtSixCharacters() {
        let vm = JoinListViewModel()

        vm.updateCode("abc2345678")

        XCTAssertEqual(vm.code, "ABC234")
        XCTAssertTrue(vm.isJoinEnabled(isJoining: false))
    }

    // Android trims before it caps, so a pasted code with a leading space still fits.
    func testTrimmingHappensBeforeTheCap() {
        let vm = JoinListViewModel()

        vm.updateCode("   abc234")

        XCTAssertEqual(vm.code, "ABC234")
    }

    func testTheDialogCopyIsAndroidsWording() {
        XCTAssertEqual(JoinListCopy.title, "Join a shared list")
        XCTAssertEqual(JoinListCopy.fieldLabel, "6-character code")
        XCTAssertEqual(JoinListCopy.placeholder, "ABC234")
        XCTAssertEqual(JoinListCopy.join, "Join")
        XCTAssertEqual(JoinListCopy.action, "Join a shared list")
    }

    // The lists screen's side of "disabled while loading": isJoining is up for the whole join.
    func testListsViewModelIsJoiningWhileTheJoinRuns() async {
        let joiner = GatedJoiner()
        let vm = ListsViewModel(repository: EmptyListsRepository(), authState: authStateFor("user-1"),
                                shareJoiner: joiner)
        vm.startJoining()

        let join = Task { await vm.joinList(code: "ABC234") }
        await joiner.waitUntilCalled()
        XCTAssertTrue(vm.isJoining)

        joiner.finish(.success("list-9"))
        await join.value
        XCTAssertFalse(vm.isJoining)
        XCTAssertFalse(vm.isJoinDialogPresented)
    }

    func testReopeningTheDialogStartsWithAnEmptyCodeAndNoError() async {
        let vm = ListsViewModel(repository: EmptyListsRepository(), authState: authStateFor("user-1"),
                                shareJoiner: FailingJoiner())
        vm.startJoining()
        await vm.joinList(code: "XXXXXX")
        XCTAssertEqual(vm.joinError, "That code didn't match any list.")
        vm.dismissJoinDialog()

        vm.startJoining()

        XCTAssertNil(vm.joinError)
        // The dialog builds a fresh field model each time it opens.
        XCTAssertEqual(JoinListViewModel().code, "")
    }
}

private struct FailingJoiner: ListJoining {
    func join(code: String) async throws -> Result<String, AppError> {
        .failure(.notFound("That code didn't match any list."))
    }
}

private final class GatedJoiner: ListJoining, @unchecked Sendable {
    private let lock = NSLock()
    private var called: CheckedContinuation<Void, Never>?
    private var wasCalled = false
    private var pending: CheckedContinuation<Result<String, AppError>, Never>?

    func join(code: String) async throws -> Result<String, AppError> {
        await withCheckedContinuation { continuation in
            let waiter = lock.withLock {
                pending = continuation
                wasCalled = true
                defer { called = nil }
                return called
            }
            waiter?.resume()
        }
    }

    func waitUntilCalled() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if wasCalled { return true }
                called = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func finish(_ result: Result<String, AppError>) {
        let continuation = lock.withLock {
            defer { pending = nil }
            return pending
        }
        continuation?.resume(returning: result)
    }
}

private struct EmptyListsRepository: ListsRepositoryProviding {
    func allLists() -> AsyncThrowingStream<[ShoppingList], any Error> {
        AsyncThrowingStream { $0.yield([]) }
    }
    func createList(name: String) async throws -> Result<String, AppError> { .failure(.unknown()) }
    func createListWithItems(name: String, drafts: [ItemDraft]) async throws -> Result<String, AppError> {
        .failure(.unknown())
    }
    func updateListName(listId: String, newName: String) async throws -> Result<Void, AppError> {
        .failure(.unknown())
    }
    func deleteListAndCaptureItems(listId: String) async throws -> Result<[ShoppingItemRecord], AppError> {
        .failure(.unknown())
    }
    func restoreListWithItems(list: ShoppingList, items: [ShoppingItemRecord]) async throws -> Result<Void, AppError> {
        .failure(.unknown())
    }
}

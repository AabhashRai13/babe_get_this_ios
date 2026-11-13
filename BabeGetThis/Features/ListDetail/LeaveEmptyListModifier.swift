import SwiftUI

/// Leaving an empty, unshared list asks first, then the list is cleaned up when the screen
/// goes (Android `ShoppingItemsScreen`'s BackHandler + leave dialog, and `onCleared`).
private struct LeaveEmptyListModifier: ViewModifier {
    @Bindable var leaveGuard: ListLeaveGuard
    let model: ListDetailViewModel
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        let asks = leaveGuard.leavingDeletesList(model)
        content
            // Android's BackHandler(enabled = leavingDeletesList): the system back (and its
            // swipe) is replaced only while leaving would delete the list.
            .navigationBarBackButtonHidden(asks)
            .toolbar {
                if asks {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if leaveGuard.backTapped(model) { dismiss() }
                        } label: {
                            Image(systemName: "chevron.backward")
                                .fontWeight(.semibold)
                        }
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("detail.back")
                    }
                }
            }
            .alert(ListLeaveGuard.title, isPresented: $leaveGuard.isConfirming) {
                Button(ListLeaveGuard.confirmTitle, role: .destructive) {
                    leaveGuard.confirmLeave()
                    dismiss()
                }
                Button(ListLeaveGuard.stayTitle, role: .cancel) { leaveGuard.stay() }
            } message: {
                Text(ListLeaveGuard.message)
            }
            .task { await leaveGuard.observeShareCode() }
            .onDisappear { leaveGuard.tearDown() }
    }
}

extension View {
    /// Adds the leave-empty-list question and the delete-if-empty teardown (DET-12).
    func leaveEmptyListGuard(_ leaveGuard: ListLeaveGuard, model: ListDetailViewModel) -> some View {
        modifier(LeaveEmptyListModifier(leaveGuard: leaveGuard, model: model))
    }
}

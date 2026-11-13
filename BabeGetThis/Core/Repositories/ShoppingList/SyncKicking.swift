/// Fire-and-forget "push soon" seam (Android `SyncKicker`). Repositories call this
/// after marking rows pendingSync so partner devices see edits promptly, without
/// the UI write waiting on the network and without repositories knowing the
/// engine exists. A dropped kick is never data loss: the flag stays set and the
/// next foreground/connectivity kick pushes it.
protocol SyncKicking: Sendable {
    func pushSoon()
}

import Foundation
import Testing
@testable import AropytEditor

@Suite("Auto save")
struct AutoSaveTests {
    @Test func preferencesDefaultPersistAndClampDelay() {
        let suiteName = "AutoSaveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AutoSavePreferences(defaults: defaults)
        #expect(preferences.mode == .never)
        #expect(preferences.delay == 1)

        preferences.mode = .afterDelay
        preferences.delay = 0.1
        #expect(AutoSavePreferences(defaults: defaults).mode == .afterDelay)
        #expect(preferences.delay == 0.5)

        preferences.delay = 100
        #expect(preferences.delay == 60)
    }

    @Test @MainActor func onChangeSerializesAndCoalescesOverlappingSaves() async throws {
        var saves = 0
        var completions: [(Bool) -> Void] = []
        let queue = AutoSaveRequestQueue(mode: .onChange, delay: 1) { completion in
            saves += 1
            completions.append(completion)
        }

        queue.contentDidChange()
        queue.contentDidChange()
        queue.contentDidChange()
        #expect(saves == 1)

        completions[0](true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(saves == 2)
        #expect(queue.isSaving)
        completions[1](true)
    }

    @Test @MainActor func afterDelayResetsTimerAndSavesOnce() async throws {
        var saves = 0
        let queue = AutoSaveRequestQueue(mode: .afterDelay, delay: 0.04) { completion in
            saves += 1
            completion(true)
        }

        queue.contentDidChange()
        try await Task.sleep(for: .milliseconds(20))
        queue.contentDidChange()
        try await Task.sleep(for: .milliseconds(80))
        #expect(saves == 1)
    }

    @Test @MainActor func neverKeepsChangesPendingUntilModeChanges() async throws {
        var saves = 0
        let queue = AutoSaveRequestQueue(mode: .never, delay: 1) { completion in
            saves += 1
            completion(true)
        }

        queue.contentDidChange()
        #expect(saves == 0)
        #expect(queue.hasPendingChanges)
        queue.preferencesDidChange(mode: .onChange, delay: 1)
        try await Task.sleep(for: .milliseconds(20))
        #expect(saves == 1)
    }
}

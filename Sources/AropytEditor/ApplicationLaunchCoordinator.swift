import Foundation

final class ApplicationLaunchCoordinator {
    typealias OpenDocument = (URL, @escaping (Bool) -> Void) -> Void
    typealias CreateNewDocument = () -> Void
    typealias Scheduler = (@escaping () -> Void) -> Void

    private let preferences: ApplicationLaunchPreferences
    private let openDocument: OpenDocument
    private let createNewDocument: CreateNewDocument
    private let schedule: Scheduler
    private var hasHandledAutomaticLaunch = false

    init(
        preferences: ApplicationLaunchPreferences,
        openDocument: @escaping OpenDocument,
        createNewDocument: @escaping CreateNewDocument,
        schedule: @escaping Scheduler = { work in DispatchQueue.main.async(execute: work) }
    ) {
        self.preferences = preferences
        self.openDocument = openDocument
        self.createNewDocument = createNewDocument
        self.schedule = schedule
    }

    /// Returns true when AppKit should perform its normal untitled-document flow.
    /// For a configured file, opening is scheduled after launch and any failure
    /// falls back to the same untitled-document behavior.
    func shouldOpenUntitledFile() -> Bool {
        guard !hasHandledAutomaticLaunch else { return false }
        hasHandledAutomaticLaunch = true

        guard let fileURL = preferences.startupFileURL() else { return true }
        schedule { [openDocument, createNewDocument] in
            openDocument(fileURL) { succeeded in
                guard !succeeded else { return }
                createNewDocument()
            }
        }
        return false
    }
}

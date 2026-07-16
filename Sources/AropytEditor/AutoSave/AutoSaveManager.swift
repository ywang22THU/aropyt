import Foundation

/// Serializes and coalesces save requests for one document.
final class AutoSaveRequestQueue {
    typealias SaveRequest = (@escaping (Bool) -> Void) -> Void

    private(set) var mode: AutoSaveMode
    private(set) var delay: TimeInterval
    private(set) var hasPendingChanges = false
    private(set) var isSaving = false

    private var saveQueuedWhileRunning = false
    private var delayedWorkItem: DispatchWorkItem?
    private let requestSave: SaveRequest

    init(mode: AutoSaveMode,
         delay: TimeInterval,
         requestSave: @escaping SaveRequest) {
        self.mode = mode
        self.delay = delay
        self.requestSave = requestSave
    }

    deinit {
        delayedWorkItem?.cancel()
    }

    func contentDidChange() {
        hasPendingChanges = true
        scheduleForCurrentMode()
    }

    func preferencesDidChange(mode: AutoSaveMode, delay: TimeInterval) {
        self.mode = mode
        self.delay = delay
        delayedWorkItem?.cancel()
        delayedWorkItem = nil
        if hasPendingChanges {
            scheduleForCurrentMode()
        }
    }

    func markSaved() {
        hasPendingChanges = false
        saveQueuedWhileRunning = false
        delayedWorkItem?.cancel()
        delayedWorkItem = nil
    }

    private func scheduleForCurrentMode() {
        switch mode {
        case .never:
            delayedWorkItem?.cancel()
            delayedWorkItem = nil
        case .onChange:
            delayedWorkItem?.cancel()
            delayedWorkItem = nil
            enqueueSave()
        case .afterDelay:
            delayedWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.delayedWorkItem = nil
                self?.enqueueSave()
            }
            delayedWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func enqueueSave() {
        guard hasPendingChanges else { return }
        if isSaving {
            saveQueuedWhileRunning = true
            return
        }

        isSaving = true
        hasPendingChanges = false
        requestSave { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSaving = false
                if !succeeded {
                    self.hasPendingChanges = true
                }

                let shouldRunFollowUp = self.saveQueuedWhileRunning
                self.saveQueuedWhileRunning = false
                guard shouldRunFollowUp, self.hasPendingChanges else { return }
                self.scheduleForCurrentMode()
            }
        }
    }
}

final class AutoSaveManager {
    static let shared = AutoSaveManager()

    typealias SaveRequest = AutoSaveRequestQueue.SaveRequest

    private final class Entry {
        weak var document: MarkdownDocument?
        let queue: AutoSaveRequestQueue

        init(document: MarkdownDocument, queue: AutoSaveRequestQueue) {
            self.document = document
            self.queue = queue
        }
    }

    private let preferences: AutoSavePreferences
    private var entries: [ObjectIdentifier: Entry] = [:]

    init(preferences: AutoSavePreferences = .shared) {
        self.preferences = preferences
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: AutoSavePreferences.didChangeNotification,
            object: preferences
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func register(document: MarkdownDocument, save: @escaping SaveRequest) {
        removeReleasedDocuments()
        let queue = AutoSaveRequestQueue(
            mode: preferences.mode,
            delay: preferences.delay,
            requestSave: save
        )
        entries[ObjectIdentifier(document)] = Entry(document: document, queue: queue)
    }

    func unregister(document: MarkdownDocument) {
        entries.removeValue(forKey: ObjectIdentifier(document))
    }

    func contentDidChange(in document: MarkdownDocument) {
        entries[ObjectIdentifier(document)]?.queue.contentDidChange()
    }

    func markSaved(_ document: MarkdownDocument) {
        entries[ObjectIdentifier(document)]?.queue.markSaved()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        removeReleasedDocuments()
        for entry in entries.values {
            entry.queue.preferencesDidChange(mode: preferences.mode, delay: preferences.delay)
        }
    }

    private func removeReleasedDocuments() {
        entries = entries.filter { $0.value.document != nil }
    }
}

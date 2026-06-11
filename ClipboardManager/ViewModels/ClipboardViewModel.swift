import AppKit
import Observation

@Observable
@MainActor
final class ClipboardViewModel {
    var items: [ClipboardItem] = []
    var selectedIndex: Int = 0
    var popupOpenCount: Int = 0
    var pendingPaste: Bool = false
    var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }

    var selectedItem: ClipboardItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    private let storage: StorageService
    private let monitor: ClipboardMonitor
    private var searchTask: Task<Void, Never>?

    init(storage: StorageService, monitor: ClipboardMonitor) {
        self.storage = storage
        self.monitor = monitor

        monitor.onNewItem = { @MainActor [weak self] item in
            self?.storage.insert(item)
            self?.refreshIfSearchEmpty()
        }
    }

    func startMonitoring() {
        monitor.start()
        items = storage.fetchAll()
    }

    func onPopupOpened() {
        popupOpenCount += 1
        searchQuery = ""
        selectedIndex = 0
        items = storage.fetchAll()
    }

    func onPopupClosed() {
        searchQuery = ""
        searchTask?.cancel()
    }

    func selectItem(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if item.contentType == .image, let data = item.rawData, let image = NSImage(data: data) {
            pb.writeObjects([image])
        } else {
            pb.setString(item.content, forType: .string)
            if item.contentType == .url, let url = URL(string: item.content) {
                pb.writeObjects([url as NSURL])
            }
        }

        // Record AFTER writing so we capture the exact post-write changeCount to skip.
        monitor.lastWrittenChangeCount = pb.changeCount

        // Signal hide() to simulate paste AFTER the previous app is activated.
        pendingPaste = true
    }

    func toggleFavorite(_ item: ClipboardItem) {
        storage.setFavorite(id: item.id, value: !item.isFavorite)
        refreshItems()
    }

    func deleteItem(_ item: ClipboardItem) {
        storage.delete(id: item.id)
        let removedIndex = selectedIndex
        refreshItems()
        selectedIndex = max(0, min(removedIndex, items.count - 1))
    }

    func clearHistory() {
        storage.clearHistory()
        refreshItems()
    }

    func moveSelection(by delta: Int) {
        selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
    }

    // MARK: - Private

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self.refreshItems()
        }
    }

    private func refreshItems() {
        if searchQuery.isEmpty {
            items = storage.fetchAll()
        } else {
            items = storage.search(searchQuery)
        }
        selectedIndex = max(0, min(selectedIndex, items.count - 1))
    }

    private func refreshIfSearchEmpty() {
        if searchQuery.isEmpty {
            items = storage.fetchAll()
        }
    }
}

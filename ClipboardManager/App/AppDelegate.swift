import AppKit
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var viewModel: ClipboardViewModel!
    private var popupController: PopupWindowController!
    private var hotkeyService: HotkeyService!
    private(set) var settings: Settings!
    private var hotkeyObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Uma segunda instância duplicaria o prompt de Acessibilidade e brigaria pelo atalho global.
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0 != NSRunningApplication.current }) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }

        settings = Settings()

        guard let sqliteManager = try? SQLiteManager() else {
            fatalError("Failed to initialize SQLite database")
        }

        let storage = StorageService(sqliteManager: sqliteManager, settings: settings)
        let monitor = ClipboardMonitor(settings: settings)

        viewModel = ClipboardViewModel(storage: storage, monitor: monitor)
        popupController = PopupWindowController(viewModel: viewModel)

        hotkeyService = HotkeyService()
        let saved = HotkeyShortcut.load()
        let status = hotkeyService.register(saved) { [weak self] in
            self?.popupController.toggle()
        }
        if status != noErr, saved != .default {
            // Conflito novo com o atalho salvo: volta ao padrão para o app continuar utilizável.
            Logger.hotkey.error("saved shortcut \(saved.displayString, privacy: .public) unavailable, falling back to default")
            hotkeyService.register(.default)
            HotkeyShortcut.default.save()
        }
        observeHotkeyChanges()

        viewModel.startMonitoring()

        // Request accessibility for auto-paste (non-blocking prompt, once per app version)
        Task { await AccessibilityService.shared.promptOnceIfNeeded() }
    }

    /// A troca de atalho chega por UserDefaults + notificação (ver `Settings.hotkey`), não pela instância.
    private func observeHotkeyChanges() {
        let center = NotificationCenter.default
        hotkeyObservers = [
            center.addObserver(forName: .hotkeyDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.applySavedHotkey() }
            },
            center.addObserver(forName: .hotkeyRecordingDidBegin, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.hotkeyService.suspend() }
            },
            center.addObserver(forName: .hotkeyRecordingDidEnd, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.hotkeyService.resume() }
            }
        ]
    }

    private func applySavedHotkey() {
        let requested = HotkeyShortcut.load()
        guard requested != hotkeyService.shortcut else { return }
        if hotkeyService.update(to: requested) { return }

        // O macOS recusou (já em uso por outro app/sistema): mantém o anterior e avisa a UI.
        hotkeyService.shortcut.save()
        NotificationCenter.default.post(name: .hotkeyRegistrationFailed, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Stay alive as a menu bar app
    }

    func openPopup() {
        popupController.show()
    }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "Favorited items will not be removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.clearHistory()
        }
    }
}

import AppKit
import Combine
import SwiftUI

@main
enum LyricsBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = PlayerModel(demo: CommandLine.arguments.contains("--demo"))
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var floatingPanel: NSPanel?
    private var exportPanel: NSSavePanel?
    private var previewWindow: NSWindow?
    private let marquee = MarqueeTextView(frame: .zero)
    private var popoverAnchorWidth: CGFloat?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 260)
        statusItem.autosaveName = "LyricsBarStatusItem"
        if let button = statusItem.button {
            // NSStatusBarButton centers a native image when its title is empty.
            // Draw the icon and scrolling text together with separate, explicit bounds.
            button.image = nil
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover)
            marquee.setAccessibilityElement(false)
            button.addSubview(marquee)
        }
        popover.contentSize = NSSize(width: 396, height: 628)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: LyricsView(model: model))
        observation = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatusItem(); self?.updateFloatingPanel() }
        }
        model.start()
        updateStatusItem()
        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePopover() }
        }
        if CommandLine.arguments.contains("--preview") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 396, height: 628),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Lyricz · Preview"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: LyricsView(model: model))
            window.center()
            window.makeKeyAndOrderFront(nil)
            previewWindow = window
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        marquee.stopAnimation()
        model.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) { model.refreshLoginStatus() }

    func popoverWillShow(_ notification: Notification) {
        // Resizing the anchor makes AppKit reposition the popover beneath the pointer.
        // Hold its width through slider edits, toggles and instrumental transitions.
        popoverAnchorWidth = statusItem.length
    }

    func popoverDidClose(_ notification: Notification) {
        popoverAnchorWidth = nil
        updateStatusItem()
    }

    func saveExcerptImage(_ data: Data, title: String, completion: @escaping (String) -> Void) {
        if let panel = exportPanel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSSavePanel()
        exportPanel = panel
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Lyricz — " + title.replacingOccurrences(of: "/", with: "-") + ".png"
        panel.canCreateDirectories = true
        panel.level = .modalPanel
        // A transient status-item popover can steal activation as it closes.
        // Finish that event before presenting the app-owned, retained save panel.
        popover.performClose(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { [weak self] response in
                defer { self?.exportPanel = nil }
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    completion("Imagem salva.")
                } catch {
                    completion("Não foi possível salvar: \(error.localizedDescription)")
                    let alert = NSAlert()
                    alert.messageText = "Não foi possível salvar a imagem"
                    alert.informativeText = error.localizedDescription
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func updateFloatingPanel() {
        guard model.floatingLyrics else { floatingPanel?.orderOut(nil); return }
        if floatingPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                                styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "Lyricz · Letra flutuante"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 280, height: 150)
            panel.contentViewController = NSHostingController(rootView: FloatingLyricsView(model: model))
            panel.setFrameAutosaveName("LyriczFloatingLyrics")
            if !panel.setFrameUsingName("LyriczFloatingLyrics") { panel.center() }
            floatingPanel = panel
        }
        if floatingPanel?.isVisible == false { floatingPanel?.orderFrontRegardless() }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let width = popoverAnchorWidth ?? model.statusBarWidth
        if statusItem.length != width { statusItem.length = width }
        marquee.frame = NSRect(x: 0, y: 0, width: width, height: button.bounds.height)
        marquee.configure(text: model.barTitle, running: model.isPlaying,
                          scroll: model.scrollLongLines, showText: !model.isBarCompact,
                          symbol: model.isBarCompact && model.showLyricsInBar ? "music.note" : "waveform",
                          speed: model.scrollSpeed)
        button.toolTip = model.track.map { "\($0.title) — \($0.artist)\n\(model.currentText)" } ?? "Lyricz · Spotify e Apple Music"
        button.setAccessibilityLabel(model.barTitle)
    }

    @objc private func togglePopover() {
        if let panel = exportPanel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        model.refreshLoginStatus()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

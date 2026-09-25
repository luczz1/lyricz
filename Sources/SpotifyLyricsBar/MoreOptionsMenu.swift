import AppKit
import SwiftUI
import LyricsCore

/// Build once when opened: playback updates must not rebuild a tracked submenu.
struct MoreOptionsMenu: NSViewRepresentable {
    let model: PlayerModel
    let showFavorites: () -> Void
    let showVersions: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("Mais opções"))!,
                              target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(L("Mais opções"))
        button.toolTip = L("Mais opções")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        // Keep callbacks current, but leave the open NSMenu and its items untouched.
        context.coordinator.parent = self
    }

    @MainActor final class Coordinator: NSObject {
        var parent: MoreOptionsMenu
        private var actions: [Int: () -> Void] = [:]
        init(_ parent: MoreOptionsMenu) { self.parent = parent }

        @objc func openMenu(_ sender: NSButton) {
            let menu = buildMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
        }

        func buildMenu() -> NSMenu {
            actions.removeAll()
            let model = parent.model
            let menu = NSMenu()
            menu.autoenablesItems = false
            func add(_ title: String, to target: NSMenu, checked: Bool = false,
                     enabled: Bool = true, action: @escaping () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = actions.count
                actions[item.tag] = action
                item.state = checked ? .on : .off
                item.isEnabled = enabled
                target.addItem(item)
            }
            add(L("Letra flutuante"), to: menu, checked: model.floatingLyrics) { model.floatingLyrics.toggle() }
            add(L("Trechos favoritos"), to: menu, action: parent.showFavorites)
            add(L("Escolher outra versão da letra"), to: menu, enabled: model.track != nil, action: parent.showVersions)
            menu.addItem(.separator())
            let players = NSMenu(title: L("Player"))
            players.autoenablesItems = false
            for preference in PlayerPreference.allCases {
                add(playerPreferenceName(preference), to: players, checked: model.playerPreference == preference) {
                    model.playerPreference = preference
                }
            }
            let playerItem = NSMenuItem(title: L("Player"), action: nil, keyEquivalent: "")
            playerItem.submenu = players
            menu.addItem(playerItem)
            add(L("Abrir Spotify"), to: menu) { model.openPlayer(.spotify) }
            add(L("Abrir Apple Music"), to: menu) { model.openPlayer(.appleMusic) }
            add(L("Reconectar"), to: menu, action: model.reconnect)
            add(L("Buscar letra novamente"), to: menu, enabled: model.track != nil, action: model.refreshLyrics)
            menu.addItem(.separator())
            add(L("Mostrar frase na barra"), to: menu, checked: model.showLyricsInBar) { model.showLyricsInBar.toggle() }
            menu.addItem(.separator())
            add(L("Sair do Lyricz"), to: menu) { NSApp.terminate(nil) }
            menu.items.last?.keyEquivalent = "q"
            return menu
        }

        @objc func performAction(_ item: NSMenuItem) { actions[item.tag]?() }
    }
}

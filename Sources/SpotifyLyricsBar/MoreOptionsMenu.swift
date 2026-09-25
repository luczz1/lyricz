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
        let button = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Mais opções")!,
                              target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Mais opções")
        button.toolTip = "Mais opções"
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
            add("Letra flutuante", to: menu, checked: model.floatingLyrics) { model.floatingLyrics.toggle() }
            add("Trechos favoritos", to: menu, action: parent.showFavorites)
            add("Escolher outra versão da letra", to: menu, enabled: model.track != nil, action: parent.showVersions)
            menu.addItem(.separator())
            let players = NSMenu(title: "Player")
            players.autoenablesItems = false
            for preference in PlayerPreference.allCases {
                add(preference.name, to: players, checked: model.playerPreference == preference) {
                    model.playerPreference = preference
                }
            }
            let playerItem = NSMenuItem(title: "Player", action: nil, keyEquivalent: "")
            playerItem.submenu = players
            menu.addItem(playerItem)
            add("Abrir Spotify", to: menu) { model.openPlayer(.spotify) }
            add("Abrir Apple Music", to: menu) { model.openPlayer(.appleMusic) }
            add("Reconectar", to: menu, action: model.reconnect)
            add("Buscar letra novamente", to: menu, enabled: model.track != nil, action: model.refreshLyrics)
            menu.addItem(.separator())
            add("Mostrar frase na barra", to: menu, checked: model.showLyricsInBar) { model.showLyricsInBar.toggle() }
            menu.addItem(.separator())
            add("Sair do Lyricz", to: menu) { NSApp.terminate(nil) }
            menu.items.last?.keyEquivalent = "q"
            return menu
        }

        @objc func performAction(_ item: NSMenuItem) { actions[item.tag]?() }
    }
}

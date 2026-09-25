import Foundation
import LyricsCore

/// Looks up UI copy in the app bundle. Media metadata and lyrics never pass through here.
func L(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}

func playerPreferenceName(_ preference: PlayerPreference) -> String {
    preference.source?.name ?? L("Automático")
}

import Foundation

public enum Shell {
    public static func quote(_ value: String) -> String {
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+=,-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safeCharacters.contains) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

import Foundation

/// Who you are to the people nearby. The name and color persist; the peer id is new every launch,
/// so a restarted app never collides with its own stale sequence numbers or invites.
struct Identity: Equatable {
    var name: String
    /// Color hue, 0...1.
    var hue: Double

    private static let nameKey = "identity.name"
    private static let hueKey = "identity.hue"

    static func load() -> Identity? {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: nameKey), !name.isEmpty else { return nil }
        let hue = defaults.object(forKey: hueKey) as? Double ?? .random(in: 0..<1)
        return Identity(name: name, hue: hue)
    }

    func save() {
        UserDefaults.standard.set(name, forKey: Self.nameKey)
        UserDefaults.standard.set(hue, forKey: Self.hueKey)
    }

    static func newPeerID() -> UInt64 {
        var id: UInt64 = 0
        while id == 0 { id = .random(in: .min ... .max) }
        return id
    }
}

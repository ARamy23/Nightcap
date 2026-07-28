import Foundation

public struct WatchedApp: Codable, Equatable, Identifiable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var isObserved: Bool

    public init(bundleID: String, displayName: String, isObserved: Bool = true) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.isObserved = isObserved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        displayName = try container.decode(String.self, forKey: .displayName)
        isObserved = try container.decodeIfPresent(Bool.self, forKey: .isObserved) ?? true
    }

    public var id: String { bundleID }
}

extension WatchedApp {
    public static let ghostty = WatchedApp(
        bundleID: "com.mitchellh.ghostty",
        displayName: "Ghostty"
    )
}

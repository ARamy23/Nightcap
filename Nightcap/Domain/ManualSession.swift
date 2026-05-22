import Foundation

enum ManualSession: Equatable {
    case finite(ManualSessionDuration)
    case indefinite

    var statusText: String {
        switch self {
        case let .finite(duration):
            "Manual: \(duration.title)"
        case .indefinite:
            "Manual: Until turned off"
        }
    }

    var assertionReason: String {
        switch self {
        case let .finite(duration):
            "Manual keep awake (\(duration.shortTitle))"
        case .indefinite:
            "Manual keep awake"
        }
    }
}

enum ManualSessionDuration: Equatable, CaseIterable {
    case minutes15
    case hour1
    case indefinite

    var title: String {
        switch self {
        case .minutes15:
            "15 min"
        case .hour1:
            "1 hour"
        case .indefinite:
            "Until turned off"
        }
    }

    var shortTitle: String {
        switch self {
        case .minutes15:
            "15 min"
        case .hour1:
            "1 hour"
        case .indefinite:
            "until turned off"
        }
    }

    var finiteDuration: Duration? {
        switch self {
        case .minutes15:
            .seconds(15 * 60)
        case .hour1:
            .seconds(60 * 60)
        case .indefinite:
            nil
        }
    }
}

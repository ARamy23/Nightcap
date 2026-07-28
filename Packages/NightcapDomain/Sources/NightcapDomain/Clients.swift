import Dependencies
import DependenciesMacros

// Interfaces only. Live implementations live in NightcapClients, which is the
// only module allowed to import AppKit, IOKit, ServiceManagement or StoreKit.
// This keeps NightcapDomain buildable on every platform, including watchOS.

// MARK: - App lifecycle

@DependencyClient
public struct AppLifecycleClient: Sendable {
    public var runningBundleIDs: @Sendable () -> Set<String> = { [] }
    public var runningApps: @Sendable () -> [WatchedApp] = { [] }
    public var events: @Sendable () -> AsyncStream<Event> = { .finished }

    public enum Event: Sendable, Equatable {
        case launched(bundleID: String)
        case terminated(bundleID: String)
        case wake
    }
}

extension AppLifecycleClient: TestDependencyKey {
    public static let testValue = AppLifecycleClient()
}

// MARK: - Power assertion

@DependencyClient
public struct PowerAssertionClient: Sendable {
    public var acquire: @Sendable (_ reason: String) -> Bool = { _ in false }
    public var release: @Sendable () -> Void
}

extension PowerAssertionClient: TestDependencyKey {
    public static let testValue = PowerAssertionClient()
}

// MARK: - Launch at login

@DependencyClient
public struct LaunchAtLoginClient: Sendable {
    public var status: @Sendable () -> LaunchAtLoginStatus = { .unknown }
    public var setEnabled: @Sendable (Bool) throws -> Void
}

extension LaunchAtLoginClient: TestDependencyKey {
    public static let testValue = LaunchAtLoginClient()
}

// MARK: - Quitting

@DependencyClient
public struct AppQuitterClient: Sendable {
    public var quit: @Sendable () -> Void
}

extension AppQuitterClient: TestDependencyKey {
    public static let testValue = AppQuitterClient(quit: {})
}

// MARK: - Review prompt

@DependencyClient
public struct ReviewPromptClient: Sendable {
    public var requestIfAppropriate: @Sendable () -> Void
}

extension ReviewPromptClient: TestDependencyKey {
    public static let testValue = ReviewPromptClient(requestIfAppropriate: {})
}

// MARK: - Registration

extension DependencyValues {
    public var appLifecycleClient: AppLifecycleClient {
        get { self[AppLifecycleClient.self] }
        set { self[AppLifecycleClient.self] = newValue }
    }

    public var powerAssertionClient: PowerAssertionClient {
        get { self[PowerAssertionClient.self] }
        set { self[PowerAssertionClient.self] = newValue }
    }

    public var launchAtLoginClient: LaunchAtLoginClient {
        get { self[LaunchAtLoginClient.self] }
        set { self[LaunchAtLoginClient.self] = newValue }
    }

    public var appQuitterClient: AppQuitterClient {
        get { self[AppQuitterClient.self] }
        set { self[AppQuitterClient.self] = newValue }
    }

    public var reviewPromptClient: ReviewPromptClient {
        get { self[ReviewPromptClient.self] }
        set { self[ReviewPromptClient.self] = newValue }
    }
}

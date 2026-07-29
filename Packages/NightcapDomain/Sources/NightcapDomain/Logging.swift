import OSLog

/// Log channels for things that fail silently by design.
///
/// The companion link is the main one: publishing runs in a detached effect
/// whose failure the user cannot see and should not be interrupted by, so
/// without a log a completely broken link is indistinguishable from a working
/// one.
extension Logger {
    private static let subsystem = "com.abdocodes.nightcap"

    static let publishing = Logger(subsystem: subsystem, category: "publishing")
}

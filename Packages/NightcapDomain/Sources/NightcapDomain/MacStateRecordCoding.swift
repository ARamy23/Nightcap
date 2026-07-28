import Foundation

/// The payload format Nightcap writes into CloudKit, and the conflict decision
/// taken when a save races.
///
/// Lives in the domain rather than the transport: this is the wire format of a
/// MacState, and keeping it here means both can be tested without a provisioned
/// iCloud container. CloudKit is unreachable in tests; what we encode and how we
/// resolve a conflict are ordinary pure logic.
public enum MacStateRecordCoding {
    public static let payloadKey = "payload"
    public static let lastUpdatedKey = "lastUpdated"

    public static func encode(_ state: MacState) throws -> (payload: Data, lastUpdated: Date) {
        (try JSONEncoder().encode(state), state.lastUpdated)
    }

    public static func decode(payload: Data) throws -> MacState {
        try JSONDecoder().decode(MacState.self, from: payload)
    }

    /// What to do when the record we fetched is stale.
    public enum ConflictResolution: Equatable {
        /// Re-apply our payload onto the server's record. The Mac is the only
        /// writer, so a conflict means our copy of the record was stale, not
        /// that someone else made a competing edit worth preserving.
        case reapplyOntoServerRecord
        /// The server gave us no record to re-apply onto, so there is nothing
        /// sensible to do but surface the failure.
        case propagateFailure
    }

    public static func resolveConflict(hasServerRecord: Bool) -> ConflictResolution {
        hasServerRecord ? .reapplyOntoServerRecord : .propagateFailure
    }

    /// A missing record is not an error: it means the Mac has never published,
    /// which is what a companion sees before the Mac app has ever run.
    public enum FetchOutcome: Equatable {
        case noMacHasPublished
        case state(MacState)
    }

    public static func interpretFetch(payload: Data?) throws -> FetchOutcome {
        guard let payload else { return .noMacHasPublished }
        return .state(try decode(payload: payload))
    }
}

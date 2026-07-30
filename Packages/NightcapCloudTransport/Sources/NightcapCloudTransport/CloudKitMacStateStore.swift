import CloudKit
import Foundation
import NightcapDomain
import os

/// Carries a MacState between the Mac and its companions through the user's own
/// private CloudKit database.
///
/// The private database is the point: the snapshot never touches a server we
/// operate, and nothing is shared between users. It does, however, mean the app
/// is no longer network-free — see PRIVACY.md.
public final class CloudKitMacStateStore: @unchecked Sendable {
    /// The container this build is entitled to use, derived from the bundle
    /// identifier so it follows whoever signed the build with no configuration.
    ///
    /// This was hardcoded to one account's container. Since the container
    /// belongs to a specific Apple account, anyone signing with their own team
    /// — the only way to run this at all — got "Couldn't get container
    /// configuration from the server" and published nothing, silently.
    ///
    /// The companions' suffixes are stripped because all three apps share one
    /// container: `…nightcap.phone` must still look for `iCloud.…nightcap`.
    /// That is also why `CKContainer.default()` is not a substitute — it would
    /// derive `iCloud.…nightcap.phone` for the companions.
    ///
    /// Reading the signed entitlement would be more literal, but
    /// `SecTaskCopyValueForEntitlement` is macOS-only: it compiles on the host
    /// and fails the iOS build.
    public static let containerIdentifier: String = {
        guard var base = Bundle.main.bundleIdentifier else {
            return "iCloud.com.abdocodes.nightcap"
        }
        for suffix in [".phone", ".watch"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
            break
        }
        return "iCloud.\(base)"
    }()

    private static let recordType = "MacState"
    /// One record per user. The Mac is the only writer.
    private static let recordName = "current-mac-state"

    private let database: CKDatabase
    private let logger = Logger(subsystem: "com.abdocodes.nightcap", category: "CloudTransport")

    public init(container: CKContainer = CKContainer(identifier: CloudKitMacStateStore.containerIdentifier)) {
        self.database = container.privateCloudDatabase
    }

    private var recordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.recordName)
    }

    // MARK: - Writing (Mac side)

    public func publish(_ state: MacState) async throws {
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }

        let encoded = try MacStateRecordCoding.encode(state)
        record[MacStateRecordCoding.payloadKey] = encoded.payload as CKRecordValue
        record[MacStateRecordCoding.lastUpdatedKey] = encoded.lastUpdated as CKRecordValue

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            switch MacStateRecordCoding.resolveConflict(hasServerRecord: error.serverRecord != nil) {
            case .propagateFailure:
                throw error
            case .reapplyOntoServerRecord:
                let serverRecord = error.serverRecord!
                serverRecord[MacStateRecordCoding.payloadKey] = encoded.payload as CKRecordValue
                serverRecord[MacStateRecordCoding.lastUpdatedKey] = encoded.lastUpdated as CKRecordValue
                _ = try await database.save(serverRecord)
            }
        }
    }

    // MARK: - Reading (companion side)

    public func fetch() async throws -> MacState? {
        do {
            let record = try await database.record(for: recordID)
            let payload = record[MacStateRecordCoding.payloadKey] as? Data
            switch try MacStateRecordCoding.interpretFetch(payload: payload) {
            case .noMacHasPublished:
                logger.debug("Record exists but carries no payload yet")
                return nil
            case let .state(state):
                // The one positive signal that the whole link works. Without it
                // a silent success and a silent failure look identical from the
                // outside, which is exactly how the container mismatch survived.
                logger.debug(
                    """
                    Fetched Mac state from \(Self.containerIdentifier, privacy: .public): \
                    awake=\(state.isAwakeHeld), watched=\(state.watchedApps.count), \
                    connection=\(state.connection.rawValue, privacy: .public), \
                    suggestHotspot=\(state.shouldSuggestHotspot)
                    """
                )
                return state
            }
        } catch let error as CKError where error.code == .unknownItem {
            // The Mac has never published. Not an error: it just isn't running.
            return nil
        }
    }

    /// Registers for push so companions update without polling. Safe to call
    /// repeatedly; an existing subscription is left alone.
    public func subscribeToChanges() async throws {
        let subscriptionID = "mac-state-changes"
        do {
            _ = try await database.subscription(for: subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Not subscribed yet, fall through and create it.
            logger.debug("Creating CloudKit subscription")
        }

        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification

        _ = try await database.save(subscription)
    }

    // MARK: - Requests from a companion back to the Mac

    /// A companion cannot change the Mac's state directly, so it leaves a
    /// request record the Mac picks up.
    public func requestObservation(bundleID: String, isObserved: Bool) async throws {
        let record = CKRecord(recordType: "ObservationRequest")
        record["bundleID"] = bundleID as CKRecordValue
        record["isObserved"] = isObserved as CKRecordValue
        record["requestedAt"] = Date() as CKRecordValue
        _ = try await database.save(record)
    }
}

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
    public static let containerIdentifier = "iCloud.com.abdocodes.nightcap"

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

        record["payload"] = try JSONEncoder().encode(state) as CKRecordValue
        record["lastUpdated"] = state.lastUpdated as CKRecordValue

        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // The Mac is the only writer, so a conflict means a stale local copy.
            // Take the server's record and re-apply, rather than dropping the update.
            guard let serverRecord = error.serverRecord else { throw error }
            serverRecord["payload"] = try JSONEncoder().encode(state) as CKRecordValue
            serverRecord["lastUpdated"] = state.lastUpdated as CKRecordValue
            _ = try await database.save(serverRecord)
        }
    }

    // MARK: - Reading (companion side)

    public func fetch() async throws -> MacState? {
        do {
            let record = try await database.record(for: recordID)
            guard let data = record["payload"] as? Data else { return nil }
            return try JSONDecoder().decode(MacState.self, from: data)
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

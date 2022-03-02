// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestStorage: SessionMessagingKitStorageProtocol, Mockable {
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case allOpenGroups
        case openGroupPublicKeys
        case userKeyPair
        case userEdKeyPair
        case openGroup
        case openGroupServer
        case openGroupImage
        case openGroupUserCount
        case openGroupSequenceNumber
        case openGroupLatestMessageId
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - Shared

    @discardableResult func write(with block: @escaping (Any) -> Void) -> Promise<Void> {
        block(())   // TODO: Pass Transaction type to prevent force-cast crashes throughout codebase
        return Promise.value(())
    }
    
    @discardableResult func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void> {
        block(())   // TODO: Pass Transaction type to prevent force-cast crashes throughout codebase
        return Promise.value(())
    }
    
    func writeSync(with block: @escaping (Any) -> Void) {
        block(())   // TODO: Pass Transaction type to prevent force-cast crashes throughout codebase
    }

    // MARK: - General

    func getUserPublicKey() -> String? { return nil }
    func getUserKeyPair() -> ECKeyPair? { return (mockData[.userKeyPair] as? ECKeyPair) }
    func getUserED25519KeyPair() -> Box.KeyPair? { return (mockData[.userEdKeyPair] as? Box.KeyPair) }
    func getUser() -> Contact? { return nil }
    func getAllContacts() -> Set<Contact> { return Set() }
    func getAllContacts(with transaction: YapDatabaseReadTransaction) -> Set<Contact> { return Set() }

    // MARK: - Closed Groups

    func getUserClosedGroupPublicKeys() -> Set<String> { return Set() }
    func getZombieMembers(for groupPublicKey: String) -> Set<String> { return Set() }
    func setZombieMembers(for groupPublicKey: String, to zombies: Set<String>, using transaction: Any) {}
    func isClosedGroup(_ publicKey: String) -> Bool { return false }

    // MARK: - Jobs

    func persist(_ job: Job, using transaction: Any) {}
    func markJobAsSucceeded(_ job: Job, using transaction: Any) {}
    func markJobAsFailed(_ job: Job, using transaction: Any) {}
    func getAllPendingJobs(of type: Job.Type) -> [Job] { return [] }
    func getAttachmentUploadJob(for attachmentID: String) -> AttachmentUploadJob? { return nil }
    func getMessageSendJob(for messageSendJobID: String) -> MessageSendJob? { return nil }
    func resumeMessageSendJobIfNeeded(_ messageSendJobID: String) {}
    func isJobCanceled(_ job: Job) -> Bool { return true }

    // MARK: - Open Groups
    
    func getAllOpenGroups() -> [String: OpenGroup] { return (mockData[.allOpenGroups] as! [String: OpenGroup]) }
    func getThreadID(for v2OpenGroupID: String) -> String? { return nil }
    func updateMessageIDCollectionByPruningMessagesWithIDs(_ messageIDs: Set<String>, using transaction: Any) {}
    
    func getOpenGroupImage(for room: String, on server: String) -> Data? { return (mockData[.openGroupImage] as? Data) }
    func setOpenGroupImage(to data: Data, for room: String, on server: String, using transaction: Any) {
        mockData[.openGroupImage] = data
    }
    
    func getOpenGroup(for threadID: String) -> OpenGroup? { return (mockData[.openGroup] as? OpenGroup) }
    func setOpenGroup(_ openGroup: OpenGroup, for threadID: String, using transaction: Any) { mockData[.openGroup] = openGroup }
    func getOpenGroupServer(name: String) -> OpenGroupAPI.Server? { return mockData[.openGroupServer] as? OpenGroupAPI.Server }
    func setOpenGroupServer(_ server: OpenGroupAPI.Server, using transaction: Any) { mockData[.openGroupServer] = server }
    
    func getUserCount(forOpenGroupWithID openGroupID: String) -> UInt64? {
        return (mockData[.openGroupUserCount] as? UInt64)
    }
    
    func setUserCount(to newValue: UInt64, forOpenGroupWithID openGroupID: String, using transaction: Any) {
        mockData[.openGroupUserCount] = newValue
    }
    
    func getOpenGroupSequenceNumber(for room: String, on server: String) -> Int64? {
        let data: [String: Int64] = ((mockData[.openGroupSequenceNumber] as? [String: Int64]) ?? [:])
        return data["\(server).\(room)"]
    }
    
    func setOpenGroupSequenceNumber(for room: String, on server: String, to newValue: Int64, using transaction: Any) {
        var updatedData: [String: Int64] = ((mockData[.openGroupSequenceNumber] as? [String: Int64]) ?? [:])
        updatedData["\(server).\(room)"] = newValue
        mockData[.openGroupSequenceNumber] = updatedData
    }
    
    func removeOpenGroupSequenceNumber(for room: String, on server: String, using transaction: Any) {
        var updatedData: [String: Int64] = ((mockData[.openGroupSequenceNumber] as? [String: Int64]) ?? [:])
        updatedData["\(server).\(room)"] = nil
        mockData[.openGroupSequenceNumber] = updatedData
    }

    func getOpenGroupInboxLatestMessageId(for server: String) -> Int64? {
        let data: [String: Int64] = ((mockData[.openGroupLatestMessageId] as? [String: Int64]) ?? [:])
        return data[server]
    }
    
    func setOpenGroupInboxLatestMessageId(for server: String, to newValue: Int64, using transaction: Any) {
        var updatedData: [String: Int64] = ((mockData[.openGroupLatestMessageId] as? [String: Int64]) ?? [:])
        updatedData[server] = newValue
        mockData[.openGroupLatestMessageId] = updatedData
    }
    
    func removeOpenGroupInboxLatestMessageId(for server: String, using transaction: Any) {
        var updatedData: [String: Int64] = ((mockData[.openGroupLatestMessageId] as? [String: Int64]) ?? [:])
        updatedData[server] = nil
        mockData[.openGroupLatestMessageId] = updatedData
    }
    
    // MARK: - Open Group Public Keys
    
    func getOpenGroupPublicKey(for server: String) -> String? {
        guard let publicKeyMap: [String: String] = mockData[.openGroupPublicKeys] as? [String: String] else {
            return (mockData[.openGroupPublicKeys] as? String)
        }
        
        return publicKeyMap[server]
    }
    
    func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any) {}

    // MARK: - Message Handling
    
    func getAllMessageRequestThreads() -> [String: TSContactThread] { return [:] }
    func getAllMessageRequestThreads(using transaction: YapDatabaseReadTransaction) -> [String: TSContactThread] { return [:] }

    func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64] { return [] }
    func addReceivedMessageTimestamp(_ timestamp: UInt64, using transaction: Any) {}
    func getOrCreateThread(for publicKey: String, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? { return nil }
    func persist(_ message: VisibleMessage, quotedMessage: TSQuotedMessage?, linkPreview: OWSLinkPreview?, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String? { return nil }
    func persist(_ attachments: [VisibleMessage.Attachment], using transaction: Any) -> [String] { return [] }
    func setAttachmentState(to state: TSAttachmentPointerState, for pointer: TSAttachmentPointer, associatedWith tsIncomingMessageID: String, using transaction: Any) {}
    func persist(_ stream: TSAttachmentStream, associatedWith tsIncomingMessageID: String, using transaction: Any) {}
}

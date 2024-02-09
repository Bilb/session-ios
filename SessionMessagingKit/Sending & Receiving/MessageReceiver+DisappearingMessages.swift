// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionSnodeKit
import SessionUIKit
import SessionUtilitiesKit

extension MessageReceiver {
    public static func updateContactDisappearingMessagesVersionIfNeeded(
        _ db: Database,
        messageVariant: Message.Variant?,
        contactId: String?,
        version: FeatureVersion?
    ) {
        guard
            let messageVariant: Message.Variant = messageVariant,
            let contactId: String = contactId,
            let version: FeatureVersion = version
        else {
            return
        }
        
        guard [ .visibleMessage, .expirationTimerUpdate ].contains(messageVariant) else { return }
        
        _ = try? Contact
            .filter(id: contactId)
            .updateAllAndConfig(
                db,
                Contact.Columns.lastKnownClientVersion.set(to: version)
            )
        
        guard Features.useNewDisappearingMessagesConfig else { return }
        
        if contactId == getUserHexEncodedPublicKey(db) {
            switch version {
                case .legacyDisappearingMessages:
                    TopBannerController.show(warning: .outdatedUserConfig)
                case .newDisappearingMessages:
                    TopBannerController.hide()
            }
        }
    }
    
    public struct MessageExpirationInfo {
        let expiresStartedAtMs: Double?
        let expiresInSeconds: TimeInterval?
        let shouldUpdateExpiry: Bool
    }
    
    public static func getMessageExpirationInfo(
        _ db: Database,
        wasRead: Bool,
        serverExpirationTimestamp: TimeInterval?,
        expiresInSeconds: TimeInterval?,
        expiresStartedAtMs: Double?,
        using dependencies: Dependencies = Dependencies()
    ) -> MessageExpirationInfo {
        var shouldUpdateExpiry: Bool = false
        let expiresStartedAtMs: Double? = {
            // Disappear after sent
            guard expiresStartedAtMs == nil else {
                return expiresStartedAtMs
            }
            
            // Disappear after read
            guard
                let expiresInSeconds: TimeInterval = expiresInSeconds,
                expiresInSeconds > 0,
                wasRead,
                let serverExpirationTimestamp: TimeInterval = serverExpirationTimestamp
            else {
                return nil
            }
            
            let nowMs: Double = Double(SnodeAPI.currentOffsetTimestampMs())
            let serverExpirationTimestampMs: Double = serverExpirationTimestamp * 1000
            let expiresInMs: Double = expiresInSeconds * 1000
            
            if serverExpirationTimestampMs <= (nowMs + expiresInMs) {
                // seems to have been shortened already
                return (serverExpirationTimestampMs - expiresInMs)
            } else {
                // consider that message unread
                shouldUpdateExpiry = true
                return (nowMs + expiresInSeconds)
            }
        }()
        
        return MessageExpirationInfo(
            expiresStartedAtMs: expiresStartedAtMs,
            expiresInSeconds: expiresInSeconds,
            shouldUpdateExpiry: shouldUpdateExpiry
        )
    }
    
    public static func getExpirationForOutgoingDisappearingMessages(
        _ db: Database,
        threadId: String,
        variant: Interaction.Variant,
        serverHash: String?,
        expireInSeconds: TimeInterval?
    ) {
        guard
            variant == .standardOutgoing,
            let serverHash: String = serverHash,
            let expireInSeconds: TimeInterval = expireInSeconds,
            expireInSeconds > 0
        else {
            return
        }
        
        let startedAtTimestampMs: Double = Double(SnodeAPI.currentOffsetTimestampMs())
        
        JobRunner.add(
            db,
            job: Job(
                variant: .getExpiration,
                behaviour: .runOnce,
                threadId: threadId,
                details: GetExpirationJob.Details(
                    expirationInfo: [serverHash: expireInSeconds],
                    startedAtTimestampMs: startedAtTimestampMs
                )
            )
        )
    }
    
    public static func updateExpiryForDisappearAfterReadMessages(
        _ db: Database,
        threadId: String,
        serverHash: String?,
        expiresInSeconds: TimeInterval?,
        expiresStartedAtMs: Double?
    ) {
        guard
            let serverHash: String = serverHash,
            let expiresInSeconds: TimeInterval = expiresInSeconds,
            let expiresStartedAtMs: Double = expiresStartedAtMs
        else {
            return
        }
        
        let expirationTimestampMs: Int64 = Int64(expiresStartedAtMs + expiresInSeconds * 1000)
        JobRunner.add(
            db,
            job: Job(
                variant: .expirationUpdate,
                behaviour: .runOnce,
                threadId: threadId,
                details: ExpirationUpdateJob.Details(
                    serverHashes: [serverHash],
                    expirationTimestampMs: expirationTimestampMs
                )
            )
        )
    }
}

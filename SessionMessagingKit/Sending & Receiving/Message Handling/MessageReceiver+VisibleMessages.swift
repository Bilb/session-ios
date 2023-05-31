// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import SessionSnodeKit
import SessionUtilitiesKit

extension MessageReceiver {
    @discardableResult public static func handleVisibleMessage(
        _ db: Database,
        threadId: String,
        threadVariant: SessionThread.Variant,
        message: VisibleMessage,
        associatedWithProto proto: SNProtoContent,
        dependencies: Dependencies = Dependencies()
    ) throws -> Int64 {
        guard let sender: String = message.sender, let dataMessage = proto.dataMessage else {
            throw MessageReceiverError.invalidMessage
        }
        
        // Note: `message.sentTimestamp` is in ms (convert to TimeInterval before converting to
        // seconds to maintain the accuracy)
        let messageSentTimestamp: TimeInterval = (TimeInterval(message.sentTimestamp ?? 0) / 1000)
        let isMainAppActive: Bool = (UserDefaults.sharedLokiProject?[.isMainAppActive]).defaulting(to: false)
        let currentUserPublicKey: String = getUserHexEncodedPublicKey(db, dependencies: dependencies)
        
        /// Only process the message if the thread `shouldBeVisible` or it was sent after the libSession buffer period
        guard
            SessionThread
                .filter(id: threadId)
                .filter(SessionThread.Columns.shouldBeVisible == true)
                .isNotEmpty(db) ||
            SessionUtil.conversationInConfig(
                db,
                threadId: threadId,
                threadVariant: threadVariant,
                visibleOnly: true
            ) ||
            SessionUtil.canPerformChange(
                db,
                threadId: threadId,
                targetConfig: {
                    switch threadVariant {
                        case .contact: return (threadId == currentUserPublicKey ? .userProfile : .contacts)
                        default: return .userGroups
                    }
                }(),
                changeTimestampMs: (message.sentTimestamp.map { Int64($0) } ?? SnodeAPI.currentOffsetTimestampMs())
            )
        else { throw MessageReceiverError.outdatedMessage }
        
        // Update profile if needed (want to do this regardless of whether the message exists or
        // not to ensure the profile info gets sync between a users devices at every chance)
        if let profile = message.profile {
            try ProfileManager.updateProfileIfNeeded(
                db,
                publicKey: sender,
                name: profile.displayName,
                avatarUpdate: {
                    guard
                        let profilePictureUrl: String = profile.profilePictureUrl,
                        let profileKey: Data = profile.profileKey
                    else { return .none }
                    
                    return .updateTo(
                        url: profilePictureUrl,
                        key: profileKey,
                        fileName: nil
                    )
                }(),
                sentTimestamp: messageSentTimestamp
            )
        }
        
        switch threadVariant {
            case .contact: break // Always continue
            
            case .community:
                // Only process visible messages for communities if they have an existing thread
                guard (try? SessionThread.exists(db, id: threadId)) == true else {
                    throw MessageReceiverError.noThread
                }
                        
            case .legacyGroup, .group:
                // Only process visible messages for groups if they have a ClosedGroup record
                guard (try? ClosedGroup.exists(db, id: threadId)) == true else {
                    throw MessageReceiverError.noThread
                }
        }
        
        // Store the message variant so we can run variant-specific behaviours
        let thread: SessionThread = try SessionThread
            .fetchOrCreate(db, id: threadId, variant: threadVariant, shouldBeVisible: nil)
        let maybeOpenGroup: OpenGroup? = {
            guard threadVariant == .community else { return nil }
            
            return try? OpenGroup.fetchOne(db, id: threadId)
        }()
        let variant: Interaction.Variant = {
            guard
                let senderSessionId: SessionId = SessionId(from: sender),
                let openGroup: OpenGroup = maybeOpenGroup
            else {
                return (sender == currentUserPublicKey ?
                    .standardOutgoing :
                    .standardIncoming
                )
            }

            // Need to check if the blinded id matches for open groups
            switch senderSessionId.prefix {
                case .blinded:
                    let sodium: Sodium = Sodium()
                    
                    guard
                        let userEdKeyPair: KeyPair = Identity.fetchUserEd25519KeyPair(db),
                        let blindedKeyPair: KeyPair = sodium.blindedKeyPair(
                            serverPublicKey: openGroup.publicKey,
                            edKeyPair: userEdKeyPair,
                            genericHash: sodium.genericHash
                        )
                    else { return .standardIncoming }
                    
                    return (sender == SessionId(.blinded, publicKey: blindedKeyPair.publicKey).hexString ?
                        .standardOutgoing :
                        .standardIncoming
                    )
                    
                case .standard, .unblinded:
                    return (sender == currentUserPublicKey ?
                        .standardOutgoing :
                        .standardIncoming
                    )
            }
        }()
        
        // Handle emoji reacts first (otherwise it's essentially an invalid message)
        if let interactionId: Int64 = try handleEmojiReactIfNeeded(
            db,
            thread: thread,
            message: message,
            associatedWithProto: proto,
            sender: sender,
            messageSentTimestamp: messageSentTimestamp
        ) {
            return interactionId
        }
        
        // Retrieve the disappearing messages config to set the 'expiresInSeconds' value
        // accoring to the config
        let disappearingMessagesConfiguration: DisappearingMessagesConfiguration = (try? thread.disappearingMessagesConfiguration.fetchOne(db))
            .defaulting(to: DisappearingMessagesConfiguration.defaultWith(thread.id))
        
        // Try to insert the interaction
        //
        // Note: There are now a number of unique constraints on the database which
        // prevent the ability to insert duplicate interactions at a database level
        // so we don't need to check for the existance of a message beforehand anymore
        let interaction: Interaction
        
        do {
            interaction = try Interaction(
                serverHash: message.serverHash, // Keep track of server hash
                threadId: thread.id,
                authorId: sender,
                variant: variant,
                body: message.text,
                timestampMs: Int64(messageSentTimestamp * 1000),
                wasRead: (
                    // Auto-mark sent messages or messages older than the 'lastReadTimestampMs' as read
                    variant == .standardOutgoing ||
                    SessionUtil.timestampAlreadyRead(
                        threadId: thread.id,
                        threadVariant: thread.variant,
                        timestampMs: Int64(messageSentTimestamp * 1000),
                        userPublicKey: currentUserPublicKey,
                        openGroup: maybeOpenGroup
                    )
                ),
                hasMention: Interaction.isUserMentioned(
                    db,
                    threadId: thread.id,
                    body: message.text,
                    quoteAuthorId: dataMessage.quote?.author
                ),
                // Note: Ensure we don't ever expire open group messages
                expiresInSeconds: (disappearingMessagesConfiguration.isEnabled && message.openGroupServerMessageId == nil ?
                    disappearingMessagesConfiguration.durationSeconds :
                    nil
                ),
                expiresStartedAtMs: nil,
                // OpenGroupInvitations are stored as LinkPreview's in the database
                linkPreviewUrl: (message.linkPreview?.url ?? message.openGroupInvitation?.url),
                // Keep track of the open group server message ID ↔ message ID relationship
                openGroupServerMessageId: message.openGroupServerMessageId.map { Int64($0) },
                openGroupWhisperMods: (message.recipient?.contains(".mods") == true),
                openGroupWhisperTo: {
                    guard
                        let recipientParts: [String] = message.recipient?.components(separatedBy: "."),
                        recipientParts.count >= 3  // 'server.roomToken.whisperTo.whisperMods'
                    else { return nil }
                    
                    return recipientParts[2]
                }()
            ).inserted(db)
        }
        catch {
            switch error {
                case DatabaseError.SQLITE_CONSTRAINT_UNIQUE:
                    guard
                        variant == .standardOutgoing,
                        let existingInteractionId: Int64 = try? thread.interactions
                            .select(.id)
                            .filter(Interaction.Columns.timestampMs == (messageSentTimestamp * 1000))
                            .filter(Interaction.Columns.variant == variant)
                            .filter(Interaction.Columns.authorId == sender)
                            .asRequest(of: Int64.self)
                            .fetchOne(db)
                    else { break }
                    
                    // If we receive an outgoing message that already exists in the database
                    // then we still need up update the recipient and read states for the
                    // message (even if we don't need to do anything else)
                    try updateRecipientAndReadStatesForOutgoingInteraction(
                        db,
                        thread: thread,
                        interactionId: existingInteractionId,
                        messageSentTimestamp: messageSentTimestamp,
                        variant: variant,
                        syncTarget: message.syncTarget
                    )
                    
                default: break
            }
            
            throw error
        }
        
        guard let interactionId: Int64 = interaction.id else { throw StorageError.failedToSave }
        
        // Update and recipient and read states as needed
        try updateRecipientAndReadStatesForOutgoingInteraction(
            db,
            thread: thread,
            interactionId: interactionId,
            messageSentTimestamp: messageSentTimestamp,
            variant: variant,
            syncTarget: message.syncTarget
        )
        
        // Parse & persist attachments
        let attachments: [Attachment] = try dataMessage.attachments
            .compactMap { proto -> Attachment? in
                let attachment: Attachment = Attachment(proto: proto)
                
                // Attachments on received messages must have a 'downloadUrl' otherwise
                // they are invalid and we can ignore them
                return (attachment.downloadUrl != nil ? attachment : nil)
            }
            .enumerated()
            .map { index, attachment in
                let savedAttachment: Attachment = try attachment.saved(db)
                
                // Link the attachment to the interaction and add to the id lookup
                try InteractionAttachment(
                    albumIndex: index,
                    interactionId: interactionId,
                    attachmentId: savedAttachment.id
                ).insert(db)
                
                return savedAttachment
            }
        
        message.attachmentIds = attachments.map { $0.id }
        
        // Persist quote if needed
        let quote: Quote? = try? Quote(
            db,
            proto: dataMessage,
            interactionId: interactionId,
            thread: thread
        )?.inserted(db)
        
        // Parse link preview if needed
        let linkPreview: LinkPreview? = try? LinkPreview(
            db,
            proto: dataMessage,
            body: message.text,
            sentTimestampMs: (messageSentTimestamp * 1000)
        )?.saved(db)
        
        // Open group invitations are stored as LinkPreview values so create one if needed
        if
            let openGroupInvitationUrl: String = message.openGroupInvitation?.url,
            let openGroupInvitationName: String = message.openGroupInvitation?.name
        {
            try LinkPreview(
                url: openGroupInvitationUrl,
                timestamp: LinkPreview.timestampFor(sentTimestampMs: (messageSentTimestamp * 1000)),
                variant: .openGroupInvitation,
                title: openGroupInvitationName
            ).save(db)
        }
        
        // Start attachment downloads if needed (ie. trusted contact or group thread)
        // FIXME: Replace this to check the `autoDownloadAttachments` flag we are adding to threads
        let isContactTrusted: Bool = ((try? Contact.fetchOne(db, id: sender))?.isTrusted ?? false)

        if isContactTrusted || thread.variant != .contact {
            attachments
                .map { $0.id }
                .appending(quote?.attachmentId)
                .appending(linkPreview?.attachmentId)
                .forEach { attachmentId in
                    JobRunner.add(
                        db,
                        job: Job(
                            variant: .attachmentDownload,
                            threadId: thread.id,
                            interactionId: interactionId,
                            details: AttachmentDownloadJob.Details(
                                attachmentId: attachmentId
                            )
                        ),
                        canStartJob: isMainAppActive
                    )
                }
        }
        
        // Cancel any typing indicators if needed
        if isMainAppActive {
            TypingIndicators.didStopTyping(db, threadId: thread.id, direction: .incoming)
        }
        
        // Update the contact's approval status of the current user if needed (if we are getting messages from
        // them outside of a group then we can assume they have approved the current user)
        //
        // Note: This is to resolve a rare edge-case where a conversation was started with a user on an old
        // version of the app and their message request approval state was set via a migration rather than
        // by using the approval process
        if thread.variant == .contact {
            try MessageReceiver.updateContactApprovalStatusIfNeeded(
                db,
                senderSessionId: sender,
                threadId: thread.id
            )
        }
        
        // Notify the user if needed
        guard variant == .standardIncoming else { return interactionId }
        
        // Use the same identifier for notifications when in backgroud polling to prevent spam
        Environment.shared?.notificationsManager.wrappedValue?
            .notifyUser(
                db,
                for: interaction,
                in: thread
            )
        
        return interactionId
    }
    
    private static func handleEmojiReactIfNeeded(
        _ db: Database,
        thread: SessionThread,
        message: VisibleMessage,
        associatedWithProto proto: SNProtoContent,
        sender: String,
        messageSentTimestamp: TimeInterval
    ) throws -> Int64? {
        guard
            let reaction: VisibleMessage.VMReaction = message.reaction,
            proto.dataMessage?.reaction != nil
        else { return nil }
        
        let maybeInteractionId: Int64? = try? Interaction
            .select(.id)
            .filter(Interaction.Columns.threadId == thread.id)
            .filter(Interaction.Columns.timestampMs == reaction.timestamp)
            .filter(Interaction.Columns.authorId == reaction.publicKey)
            .filter(Interaction.Columns.variant != Interaction.Variant.standardIncomingDeleted)
            .asRequest(of: Int64.self)
            .fetchOne(db)
        
        guard let interactionId: Int64 = maybeInteractionId else {
            throw StorageError.objectNotFound
        }
        
        let sortId = Reaction.getSortId(
            db,
            interactionId: interactionId,
            emoji: reaction.emoji
        )
        
        switch reaction.kind {
            case .react:
                let reaction: Reaction = try Reaction(
                    interactionId: interactionId,
                    serverHash: message.serverHash,
                    timestampMs: Int64(messageSentTimestamp * 1000),
                    authorId: sender,
                    emoji: reaction.emoji,
                    count: 1,
                    sortId: sortId
                ).inserted(db)
                
                if sender != getUserHexEncodedPublicKey(db) {
                    Environment.shared?.notificationsManager.wrappedValue?
                        .notifyUser(
                            db,
                            forReaction: reaction,
                            in: thread
                        )
                }
            case .remove:
                try Reaction
                    .filter(Reaction.Columns.interactionId == interactionId)
                    .filter(Reaction.Columns.authorId == sender)
                    .filter(Reaction.Columns.emoji == reaction.emoji)
                    .deleteAll(db)
        }
        
        return interactionId
    }
    
    private static func updateRecipientAndReadStatesForOutgoingInteraction(
        _ db: Database,
        thread: SessionThread,
        interactionId: Int64,
        messageSentTimestamp: TimeInterval,
        variant: Interaction.Variant,
        syncTarget: String?
    ) throws {
        guard variant == .standardOutgoing else { return }
        
        // Immediately update any existing outgoing message 'RecipientState' records to be 'sent'
        _ = try? RecipientState
            .filter(RecipientState.Columns.interactionId == interactionId)
            .filter(RecipientState.Columns.state != RecipientState.State.sent)
            .updateAll(db, RecipientState.Columns.state.set(to: RecipientState.State.sent))
        
        // Create any addiitonal 'RecipientState' records as needed
        switch thread.variant {
            case .contact:
                if let syncTarget: String = syncTarget {
                    try RecipientState(
                        interactionId: interactionId,
                        recipientId: syncTarget,
                        state: .sent
                    ).save(db)
                }
                
            case .legacyGroup, .group:
                try GroupMember
                    .filter(GroupMember.Columns.groupId == thread.id)
                    .fetchAll(db)
                    .forEach { member in
                        try RecipientState(
                            interactionId: interactionId,
                            recipientId: member.profileId,
                            state: .sent
                        ).save(db)
                    }
                
            case .community:
                try RecipientState(
                    interactionId: interactionId,
                    recipientId: thread.id, // For open groups this will always be the thread id
                    state: .sent
                ).save(db)
        }
    
        // For outgoing messages mark all older interactions as read (the user should have seen
        // them if they send a message - also avoids a situation where the user has "phantom"
        // unread messages that they need to scroll back to before they become marked as read)
        try Interaction.markAsRead(
            db,
            interactionId: interactionId,
            threadId: thread.id,
            threadVariant: thread.variant,
            includingOlder: true,
            trySendReadReceipt: false
        )
        
        // Process any PendingReadReceipt values
        let maybePendingReadReceipt: PendingReadReceipt? = try PendingReadReceipt
            .filter(PendingReadReceipt.Columns.threadId == thread.id)
            .filter(PendingReadReceipt.Columns.interactionTimestampMs == Int64(messageSentTimestamp * 1000))
            .fetchOne(db)
        
        if let pendingReadReceipt: PendingReadReceipt = maybePendingReadReceipt {
            try Interaction.markAsRead(
                db,
                recipientId: thread.id,
                timestampMsValues: [pendingReadReceipt.interactionTimestampMs],
                readTimestampMs: pendingReadReceipt.readTimestampMs
            )
            
            _ = try pendingReadReceipt.delete(db)
        }
    }
}

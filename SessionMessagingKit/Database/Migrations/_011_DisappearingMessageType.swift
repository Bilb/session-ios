// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _011_DisappearingMessageType: Migration {
    static let target: TargetMigrations.Identifier = .messagingKit
    static let identifier: String = "DisappearingMessageType"
    static let needsConfigSync: Bool = false
    static let minExpectedRunDuration: TimeInterval = 0.1
    
    static func migrate(_ db: GRDB.Database) throws {
        try db.alter(table: DisappearingMessagesConfiguration.self) { t in
            t.add(.type, .integer)
        }
        
        func updateDisappearingMessageType(_ db: GRDB.Database, id: String, type: DisappearingMessagesConfiguration.DisappearingMessageType) throws {
            _ = try DisappearingMessagesConfiguration
                .filter(DisappearingMessagesConfiguration.Columns.threadId == id)
                .updateAll(
                    db,
                    DisappearingMessagesConfiguration.Columns.type.set(to: type)
                )
        }
        
        try DisappearingMessagesConfiguration
            .filter(DisappearingMessagesConfiguration.Columns.isEnabled == true)
            .fetchAll(db)
            .forEach { config in
                if let thread = try? SessionThread.fetchOne(db, id: config.threadId) {
                    guard !thread.isNoteToSelf(db) else {
                        try updateDisappearingMessageType(db, id: config.threadId, type: .disappearAfterSend)
                        return
                    }
                    
                    switch thread.variant {
                        case .contact: try updateDisappearingMessageType(db, id: config.threadId, type: .disappearAfterRead)
                        case .closedGroup: try updateDisappearingMessageType(db, id: config.threadId, type: .disappearAfterSend)
                        case .openGroup: return
                    }
                }
            }
        
        Storage.update(progress: 1, for: self, in: target) // In case this is the last migration
    }
}


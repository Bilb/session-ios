//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SessionServiceKit

@objc
public class OWS114RemoveDynamicInteractions: OWSDatabaseMigration {

    // MARK: - Dependencies

    // MARK: -

    // Increment a similar constant for each migration.
    @objc
    class func migrationId() -> String {
        return "114"
    }

    override public func runUp(completion: @escaping OWSDatabaseMigrationCompletion) {
        Logger.debug("")
        BenchAsync(title: "\(self.logTag)") { (benchCompletion) in
            self.doMigrationAsync(completion: {
                benchCompletion()
                completion()
            })
        }
    }

    private func doMigrationAsync(completion : @escaping OWSDatabaseMigrationCompletion) {
        DispatchQueue.global().async {
            try! Storage.writeSync { transaction in
                guard let dbView = TSDatabaseView.threadSpecialMessagesDatabaseView(transaction) as? YapDatabaseViewTransaction else {
                    owsFailDebug("Couldn't load db view.")
                    return
                }

                var interactionsToDelete = [TSInteraction]()
                let groupIds = dbView.allGroups()
                for groupId in groupIds {
                    dbView.enumerateKeysAndObjects(inGroup: groupId) { (_: String, _: String, object: Any, _: UInt, _: UnsafeMutablePointer<ObjCBool>) in
                        guard let interaction = object as? TSInteraction else {
                            owsFailDebug("Invalid database entity: \(type(of: object)).")
                            return
                        }
                        guard interaction.isDynamicInteraction() else {
                            return
                        }
                        interactionsToDelete.append(interaction)
                    }
                }

                for interaction in interactionsToDelete {
                    Logger.debug("Cleaning up interaction: \(type(of: interaction)).")
                    interaction.remove(with: transaction)
                }

                self.save(with: transaction)
            }

            completion()
        }
    }
}

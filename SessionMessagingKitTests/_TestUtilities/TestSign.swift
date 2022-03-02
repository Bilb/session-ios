// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class TestSign: SignType, Mockable {
    var PublicKeyBytes: Int = 32
    
    // MARK: - Mockable
    
    enum DataKey: Hashable {
        case signature
        case verify
        case toX25519
    }
    
    typealias Key = DataKey
    
    var mockData: [DataKey: Any] = [:]
    
    // MARK: - SignType
    
    func signature(message: Bytes, secretKey: Bytes) -> Bytes? {
        return (mockData[.signature] as? Bytes)
    }
    
    func verify(message: Bytes, publicKey: Bytes, signature: Bytes) -> Bool {
        return (mockData[.verify] as! Bool)
    }
    
    func toX25519(ed25519PublicKey: Bytes) -> Bytes? {
        return (mockData[.toX25519] as? Bytes)
    }
}

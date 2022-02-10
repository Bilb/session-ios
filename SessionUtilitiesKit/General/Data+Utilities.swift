import Foundation

public extension Data {

    func removingIdPrefixIfNeeded() -> Data {
        var result = self
        if result.count == 33 && IdPrefix(with: result.toHexString()) != nil { result.removeFirst() }
        return result
    }
    
    func appending(_ other: Data) -> Data {
        var mutableData: Data = Data()
        mutableData.append(self)
        mutableData.append(other)
        
        return mutableData
    }
    
    func appending(_ other: [UInt8]) -> Data {
        var mutableData: Data = Data()
        mutableData.append(self)
        mutableData.append(contentsOf: other)
        
        return mutableData
    }
}

@objc public extension NSData {
    
    @objc func removingIdPrefixIfNeeded() -> NSData {
        var result = self as Data
        if result.count == 33 && IdPrefix(with: result.toHexString()) != nil { result.removeFirst() }
        return result as NSData
    }
}

// MARK: - Decoding

public extension Data {
    func decoded<T: Decodable>(as type: T.Type, customError: Error? = nil) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: self)
        }
        catch let error {
            throw (customError ?? error)
        }
    }
}

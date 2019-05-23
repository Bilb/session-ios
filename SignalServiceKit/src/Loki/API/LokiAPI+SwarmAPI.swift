import PromiseKit

public extension LokiAPI {
    
    // MARK: Settings
    private static let minimumSnodeCount = 2 // TODO: For debugging purposes
    private static let targetSnodeCount = 3 // TODO: For debugging purposes
    private static let defaultSnodePort: UInt16 = 8080
    
    // MARK: Caching
    private static let swarmCacheKey = "swarmCacheKey"
    private static let swarmCacheCollection = "swarmCacheCollection"
    
    fileprivate static var swarmCache: [String:[Target]] = [:]
    
    @objc public static func loadSwarmCache() {
        var result: [String:[Target]]? = nil
        storage.dbReadConnection.read { transaction in
            let intermediate = transaction.object(forKey: swarmCacheKey, inCollection: swarmCacheCollection) as! [String:[TargetWrapper]]?
            result = intermediate?.mapValues { $0.map { Target(from: $0) } }
        }
        swarmCache = result ?? [:]
    }
    
    private static func saveSwarmCache() {
        let intermediate = swarmCache.mapValues { $0.map { TargetWrapper(from: $0) } }
        storage.dbReadWriteConnection.readWrite { transaction in
            transaction.setObject(intermediate, forKey: swarmCacheKey, inCollection: swarmCacheCollection)
        }
    }
    
    // MARK: Internal API
    private static func getRandomSnode() -> Promise<Target> {
        return Promise<Target> { seal in
            seal.fulfill(Target(address: "http://13.238.53.205", port: 8080)) // TODO: For debugging purposes
        }
    }
    
    private static func getSwarm(for hexEncodedPublicKey: String) -> Promise<[Target]> {
        if let cachedSwarm = swarmCache[hexEncodedPublicKey], cachedSwarm.count >= minimumSnodeCount {
            return Promise<[Target]> { $0.fulfill(cachedSwarm) }
        } else {
            let parameters: [String:Any] = [ "pubKey" : hexEncodedPublicKey ]
            return getRandomSnode().then { invoke(.getSwarm, on: $0, associatedWith: hexEncodedPublicKey, parameters: parameters) }.map { parseTargets(from: $0) }.get { swarm in
                swarmCache[hexEncodedPublicKey] = swarm
                saveSwarmCache()
            }
        }
    }
    
    internal static func getTargetSnodes(for hexEncodedPublicKey: String) -> Promise<[Target]> {
        // shuffled() uses the system's default random generator, which is cryptographically secure
        return getSwarm(for: hexEncodedPublicKey).map { Array($0.shuffled().prefix(targetSnodeCount)) }
    }
    
    // MARK: Parsing
    private static func parseTargets(from rawResponse: Any) -> [Target] {
        // TODO: For debugging purposes
        // ========
        let target = Target(address: "http://13.238.53.205", port: defaultSnodePort)
        return Array(repeating: target, count: 3)
        // ========
//        guard let json = rawResponse as? JSON, let addresses = json["snodes"] as? [String] else {
//            Logger.warn("[Loki] Failed to parse targets from: \(rawResponse).")
//            return []
//        }
//        return addresses.map { Target(address: $0, port: defaultSnodePort) }
    }
}

// MARK: Error Handling
internal extension Promise {
    
    internal func handlingSwarmSpecificErrorsIfNeeded(for target: LokiAPI.Target, associatedWith hexEncodedPublicKey: String) -> Promise<T> {
        return recover { error -> Promise<T> in
            if let error = error as? NetworkManagerError {
                switch error.statusCode {
                case 0:
                    // The snode is unreachable; usually a problem with LokiNet
                    Logger.warn("[Loki] There appears to be a problem with LokiNet.")
                case 421:
                    // The snode isn't associated with the given public key anymore
                    let swarm = LokiAPI.swarmCache[hexEncodedPublicKey]
                    if var swarm = swarm, let index = swarm.firstIndex(of: target) {
                        swarm.remove(at: index)
                        LokiAPI.swarmCache[hexEncodedPublicKey] = swarm
                    }
                default: break
                }
            }
            throw error
        }
    }
}
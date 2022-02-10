
public extension Array where Element : CustomStringConvertible {

    var prettifiedDescription: String {
        return "[ " + map { $0.description }.joined(separator: ", ") + " ]"
    }
}

public extension Array {
    func appending(_ other: Element) -> [Element] {
        var updatedArray: [Element] = self
        updatedArray.append(other)

        return updatedArray
    }
    
    func appending(_ other: [Element]) -> [Element] {
        var updatedArray: [Element] = self
        updatedArray.append(contentsOf: other)

        return updatedArray
    }
}

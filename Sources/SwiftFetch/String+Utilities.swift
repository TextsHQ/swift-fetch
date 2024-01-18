import Foundation

extension BidirectionalCollection<UnicodeScalar> {
    fileprivate func trimming(_ set: CharacterSet) -> Range<Index>? {
        guard let start = firstIndex(where: { !set.contains($0) }),
              let last = lastIndex(where: { !set.contains($0) }) else {
            return nil
        }
        let end = index(after: last)
        return start..<end
    }
}

extension Substring {
    public func trimming(_ set: CharacterSet) -> Substring {
        unicodeScalars.trimming(set).map { self[$0] } ?? .init()
    }
}

extension String {
    public func trimming(_ set: CharacterSet) -> Substring {
        self[...].trimming(set)
    }
}

import Foundation
import NodeAPI

extension NodeTypedArray<UInt8> {
    /// Bridges the buffer's contents to `Data`, potentially avoiding a copy.
    ///
    /// - Parameter threshold: The minimum length of the data for which no-copy
    /// bridging occurs. Under this length, performs a copy. The default value
    /// is 512. Pass 0 to never copy.
    ///
    /// No-copy bridging has a cost: the `TypedArray` has to be retained while
    /// the `Data` is alive. When the `Data` is deallocated, the `TypedArray` is
    /// relinquished to Node's garbage collector asynchronously, which may have
    /// a non-negligible cost.
    func dataNoCopy(threshold: Int = 512) throws -> Data {
        try withUnsafeMutableBytes { bytes in
            guard bytes.count >= threshold else { return Data(buffer: bytes) }
            guard let base = bytes.baseAddress else { return Data() }
            return Data(
                bytesNoCopy: base,
                count: bytes.count,
                // the buffer is alive as long as the receiver is
                deallocator: .custom { _, _ in _ = self }
            )
        }
    }
}

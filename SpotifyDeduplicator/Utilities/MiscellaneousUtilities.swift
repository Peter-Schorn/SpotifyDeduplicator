import Foundation
import SwiftUI
import Combine
import SpotifyWebAPI

public extension Set where Element == AnyCancellable {
    
    mutating func cancellAll() {
        for cancellable in self {
            cancellable.cancel()
        }
        self.removeAll()
        
    }

}

public extension Collection where Index == Int {

    /// Splits the collection into an array of arrays,
    /// each of which will have the specified size.
    func chunked(size: Int) -> [[Element]] {
        return stride(from: 0, to: self.count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, self.count)])
        }
    }

}

public extension Sequence where Element == SpotifyImage {
    
    var smallest: SpotifyImage? {
        
        // areInIncreasingOrder
        // A predicate that returns true if its first argument should
        // be ordered before its second argument; otherwise, false.
        return self.min(by: { lhs, rhs in
            (lhs.width ?? 0) * (lhs.height ?? 0) <
            (rhs.width ?? 0) * (rhs.height ?? 0)
        })
    }

}


enum KeychainKeys {
    static let authorizationManager = "authorizationManager"
    static let userId = "userId"
}

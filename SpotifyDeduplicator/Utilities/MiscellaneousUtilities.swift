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

extension URIsWithPositionsContainer {
    
    init(
        _ playlistItems: [(PlaylistItem, index: Int)],
        snapshotId: String? = nil
    ) {
        
        let urisWithPositionsDict: [String: [Int]] = playlistItems.reduce(
            into: [:]
        ) { dictionary, playlistItem in
            guard let uri = playlistItem.0.uri else { return }
            dictionary[uri, default: []].append(playlistItem.index)
        }
        
        let urisWithPositions: [URIWithPositions] = urisWithPositionsDict.reduce(
            into: []
        ) { urisWithPositions, nextItem in
            urisWithPositions.append(
                .init(uri: nextItem.key, positions: nextItem.value)
            )
        }
        
        self.init(
            snapshotId: snapshotId,
            urisWithPositions: urisWithPositions
        )
    }

}

public extension MutableCollection {
    
    /**
     Calls the provided closure for each element in self,
     passing in the index of an element and a reference to it
     that can be mutated.
     
     Example usage:
     ```
     var numbers = [0, 1, 2, 3, 4, 5]

     numbers.mutateEach { indx, element in
         if [1, 5].contains(indx) { return }
         element *= 2
     }

     print(numbers)
     // [0, 1, 4, 6, 8, 5]
     ```
     */
    mutating func mutateEach(
        _ modifyElement: (Index, inout Element) throws -> Void
    ) rethrows {
        
        for indx in self.indices {
            try modifyElement(indx, &self[indx])
        }

    }

}

import Foundation
import SwiftUI
import Combine

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

public extension RangeReplaceableCollection where Element == AnyCancellable {
    
    mutating func cancellAll() {
        for cancellable in self {
            cancellable.cancel()
        }
        self.removeAll()
        
    }

    
}

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


enum KeychainKeys {
    static let authorizationManager = "authorizationManager"
    static let userId = "userId"
}

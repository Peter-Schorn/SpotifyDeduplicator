import Foundation
import SwiftUI

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


enum KeychainKeys {
    static let authorizationManager = "authorizationManager"
    static let userId = "userId"
}

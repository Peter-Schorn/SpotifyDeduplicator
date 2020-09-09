import Foundation
import SwiftUI

extension Text {
    
    func lightSecondaryTitle() -> some View {
        return self
            .font(.title)
            .fontWeight(.light)
            .foregroundColor(.secondary)
    }
    
    func deDuplicateTextStyle() -> some View {
        return self
            .font(.title)
            .fontWeight(.light)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

}

extension View {
    
    func eraseToAnyView() -> AnyView {
        return AnyView(self)
    }

}

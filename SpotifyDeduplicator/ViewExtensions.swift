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
    
    func deDuplicateButtonStyle() -> some View {
        return self
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .frame(width: 300, height: 60)
            .background(Color.green)
            .clipShape(Capsule())
            .shadow(radius: 10)
    }
    
    func eraseToAnyView() -> AnyView {
        return AnyView(self)
    }

}

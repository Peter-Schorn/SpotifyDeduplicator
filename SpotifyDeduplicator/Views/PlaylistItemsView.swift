import SwiftUI

struct PlaylistItemsView: View {
    var body: some View {
        List {
            ForEach(0..<10) { i in
                Text("Track \(i)")
            }
        }
    }
}

struct PlaylistItemsView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistItemsView()
    }
}

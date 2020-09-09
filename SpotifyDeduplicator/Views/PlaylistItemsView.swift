import SwiftUI
import CoreData
import Combine

struct PlaylistItemsView: View {
    
    @EnvironmentObject var spotify: Spotify
    @ObservedObject var playlist: CDPlaylist
    
    var body: some View {
        Group {
            if playlist.duplicatesCount == 0 {
                Text("No Duplicates")
                    .lightSecondaryTitle()
            }
            else {
                List(playlist.duplicatePlaylistItems, id: \.0) { playlist in
                    Text(playlist.0.name)
                }
            }
        }
    }
}

// struct PlaylistItemsView_Previews: PreviewProvider {
//     static var previews: some View {
//         PlaylistItemsView()
//     }
// }

import SwiftUI
import CoreData
import Combine
import SpotifyWebAPI

struct PlaylistItemsListView: View {

    fileprivate static var debug = false
    
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var spotify: Spotify

    @ObservedObject var playlist: CDPlaylist
    
    @State private var deDuplicateCancellable: AnyCancellable? = nil
    
    var body: some View {
        Group {
            if playlist.duplicatesCount == 0 && !Self.debug {
                VStack {
                    header
                    Spacer()
                    Text("No Duplicates")
                        .lightSecondaryTitle()
                    Spacer()
                }
            }
            else {
                ZStack {
                    List {
                        header
                        ForEach(playlist.duplicatePlaylistItems, id: \.0) { item in
                            PlaylistItemView(playlistItem: item.0)
                        }
                        Rectangle()
                        .fill(Color.clear)
                        .frame(height: 50)
                    }
                    VStack {
                        Spacer()
                        Button(action: deDuplicate) {
                            buttonViewText
                                .deDuplicateButtonStyle()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .allowsHitTesting(
                            spotify.isAuthorized &&
                                    !playlist.isDeduplicating
                        )
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        
    }
    
    
    var header: some View {
        VStack {
            playlistImage
                .padding(.horizontal, 20)
            Text(playlist.name ?? "No Name")
                .font(.largeTitle)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if playlist.duplicatesCount > 0 {
                if playlist.duplicatesCount == 1 {
                    Text("1 Duplicate")
                        .foregroundColor(.secondary)
                }
                else {
                    Text("\(playlist.duplicatesCount) Duplicates")
                        .foregroundColor(.secondary)
                }
            }
            Divider()
        }
        .padding()
        .padding(.top, 20)
    }
    
    var playlistImage: some View {
        (playlist.image ?? Image(.spotifyAlbumPlaceholder))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .cornerRadius(20)
            .shadow(radius: 20)
    }
    
    var buttonViewText: AnyView {
        
        if playlist.isDeduplicating {
            return HStack {
                ActivityIndicator(
                    isAnimating: .constant(true),
                    style: .large
                )
                .scaleEffect(0.8)
                Text("De-Duplicating")
                    .deDuplicateTextStyle()
            }
            .eraseToAnyView()
        }
        
        return Text("De-Duplicate")
            .deDuplicateTextStyle()
            .eraseToAnyView()
    }
    
    func deDuplicate() {
        let totalDuplicateItems = playlist.duplicatesCount
        if totalDuplicateItems == 0 { return }
        playlist.deDuplicate(spotify)
        deDuplicateCancellable = playlist.finishedDeDuplicating
            .receive(on: RunLoop.main)
            .sink {
                if totalDuplicateItems == 1 {
                    self.spotify.alertTitle = """
                        Removed 1 Duplicate from \
                        \(self.playlist.name ?? "No Name")
                        """
                }
                else {
                    self.spotify.alertTitle = """
                        Removed \(totalDuplicateItems) Duplicates from \
                        \(self.playlist.name ?? "No Name")
                        """
                }
                self.spotify.alertMessage = ""
                self.spotify.alertIsPresented = true
            }
    }

}

 struct PlaylistItemsListView_Previews: PreviewProvider {
    
    static let track = Track(
        name: "Recently Played",
        album: nil,
        artists: nil,
        uri: nil,
        id: nil,
        isLocal: false,
        popularity: nil,
        durationMS: nil,
        trackNumber: nil,
        isExplicit: true,
        isPlayable: nil,
        href: nil,
        previewURL: nil,
        externalURLs: nil,
        externalIds: nil,
        availableMarkets: nil,
        linkedFrom: nil,
        restrictions: nil,
        discNumber: nil,
        type: .track
    )
    
    static var playlist: CDPlaylist {
        let playlist = CDPlaylist(
            context: managedObjectContext
        )
        playlist.name = "This is Jimi Hendrix"
        let imageData = UIImage(.jinxAlbum)!.pngData()!
        playlist.imageData = imageData
        
//        let duplicateTrack = (PlaylistItem.track(track), index: 5)
        
//        playlist.duplicatePlaylistItems = [
//            duplicateTrack
//        ]
        
        PlaylistItemsListView.debug = true
        return playlist
    }
    
    static let managedObjectContext = NSManagedObjectContext(
        concurrencyType: .mainQueueConcurrencyType
    )
    
    static var previews: some View {
        NavigationView {
            PlaylistItemsListView(playlist: playlist)
                .environmentObject(Spotify())
                .environment(\.managedObjectContext, managedObjectContext)
                .navigationBarTitle(
                    Text("Spotify De-Duplicator"),
                    displayMode: .inline
                )
        }
    }
    
 }

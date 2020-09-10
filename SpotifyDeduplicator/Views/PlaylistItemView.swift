import SwiftUI
import CoreData
import Combine
import SpotifyWebAPI

struct PlaylistItemView: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext

    @EnvironmentObject var spotify: Spotify
    
    @FetchRequest var savedAlbums: FetchedResults<CDAlbum>
    
    @State private var cancellables: Set<AnyCancellable> = []
    @State private var image = Image(.spotifyAlbumPlaceholder)
    
    var playlistItem: PlaylistItem
    
    init(playlistItem: PlaylistItem) {
        self.playlistItem = playlistItem
        
        let albumURI: String?
        switch playlistItem {
            case .track(let track):
                albumURI = track.album?.uri
            case .episode(let episode):
                albumURI = episode.show?.uri
        }
        Loggers.playlistItemView.trace(
            "album URI for \(playlistItem.name): " +
            (albumURI ?? "nil")
        )
        
        self._savedAlbums = FetchRequest(
            entity: CDAlbum.entity(),
            sortDescriptors: [
                .init(keyPath: \CDAlbum.name, ascending: true)
            ],
            predicate: .init(
                format: "uri = %@", albumURI ?? ""
            )
        )
    }
    
    var body: some View {
        HStack {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
                .cornerRadius(4)
            Text(title)
            Spacer()
        }
        .onAppear(perform: loadImage)
        .onReceive(spotify.$isAuthorized) { _ in
            self.loadImage()
        }
        
    }
    
    var title: String {
        var title = playlistItem.name
        switch playlistItem {
            case .track(let track):
                if let artistName = track.artists?.first?.name {
                    title += " - \(artistName)"
                }
            case .episode(let episode):
                if let showName = episode.show?.name {
                    title += " - \(showName)"
                }
        }
        return title
    }
    
    func loadImage() {
        
        guard let album = savedAlbums.first else {
            Loggers.playlistItemView.warning(
                "couldn't get saved album"
            )
            return
        }
        
        if let image = album.image {
            self.image = image
            return
        }
        
        guard spotify.isAuthorized else {
            Loggers.loadingImages.notice(
                "tried to load image without authorization"
            )
            return
        }
        
        album.loadImage(spotify)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        Loggers.loadingImages.trace(
                            "couldn't load image for " +
                            "\(album.name ?? "nil"): \(error)"
                        )
                    }
                },
                receiveValue: { image in
                    self.image = image
                    if self.managedObjectContext.hasChanges {
                        do {
                            try self.managedObjectContext.save()
        
                        } catch {
                            print(
                                "\(#function) line \(#line): " +
                                "couldn't save context:\n\(error)"
                            )
                        }
                    }
                }
            )
            .store(in: &self.cancellables)
        

    }
    
}

//struct PlaylistItemView_Previews: PreviewProvider {
//    static var previews: some View {
//        PlaylistItemView()
//    }
//}

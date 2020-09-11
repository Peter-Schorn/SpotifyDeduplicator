import SwiftUI
import Combine
import CoreData
import SpotifyWebAPI

struct PlaylistCellView: View {
    
    @EnvironmentObject var spotify: Spotify
    @Environment(\.managedObjectContext) var managedObjectContext
    
    @State private var cancellables: Set<AnyCancellable> = []
    @State private var image = Image(.spotifyAlbumPlaceholder)
    
    @ObservedObject var playlist: CDPlaylist

    var playlistText: Text {
        var name = Text(playlist.name ?? "No Name")
        if playlist.tracksCount == 1 {
            name = name + Text(" - 1 track")
                .foregroundColor(.secondary)
        }
        else if playlist.tracksCount > 0 {
            name = name + Text(" - \(playlist.tracksCount) tracks")
                .foregroundColor(.secondary)
                
        }
        return name
            .font(.headline)
    }
    
    var body: some View {
        NavigationLink(
            destination: PlaylistItemsListView(playlist: playlist)
        ) {
            HStack {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 70, height: 70)
                    .cornerRadius(5)
                    .shadow(radius: 5)
                VStack {
                    HStack {
                        playlistText
                        if playlist.isCheckingForDuplicates ||
                                playlist.isDeduplicating {
                            ActivityIndicator(
                                isAnimating: .constant(true),
                                style: .medium
                            )
                        }
                        Spacer()
                    }
                    if !playlist.isCheckingForDuplicates &&
                            playlist.didCheckForDuplicates &&
                            !playlist.isDeduplicating {
                        HStack {
                            if playlist.duplicatesCount == 0 {
                                Text("No Duplicates")
                            }
                            else if playlist.duplicatesCount == 1 {
                                Text("1 Duplicate")
                            }
                            else {
                                Text("\(playlist.duplicatesCount) Duplicates")
                            }
                            Spacer()
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(.all, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .onAppear(perform: loadImage)
        .onReceive(spotify.$isAuthorized) { _ in
            self.loadImage()
        }
        .onReceive(playlist.objectWillChange) { _ in
            self.loadImage()
        }
    }
    
    func loadImage() {
        
        if let image = playlist.image,
                // if the snapshot id has changed, then the playlist image
                // might have changed, so don't use the image saved in CoreData.
                playlist.snapshotId == playlist.lastImageRequestedSnapshotId {
            DispatchQueue.main.async {
                self.image = image
            }
            
            return
        }

        guard spotify.isAuthorized else {
            Loggers.loadingImages.notice(
                "tried to load image without authorization"
            )
            return
        }
        
        let cancellable = playlist.loadImage(spotify)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        Loggers.loadingImages.trace(
                            "couldn't load image for " +
                            "\(self.playlist.name ?? "nil"): \(error)"
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
        
        DispatchQueue.main.async {
            self.cancellables.insert(cancellable)
        }
    }
    
}

struct PlaylistView_Previews: PreviewProvider {
    
    static let playlist: CDPlaylist = {
        let playlist = CDPlaylist(
            context: managedObjectContext
        )
        playlist.name = "This is Annabelle"
        let imageData = UIImage(.annabelleOnChair)!.pngData()!
        playlist.imageData = imageData
        playlist.didCheckForDuplicates = true
        return playlist
    }()
    
    static let playlist2: CDPlaylist = {
        let playlist = CDPlaylist(
            context: managedObjectContext
        )
        playlist.name = "Crumbb"
        let imageData = UIImage(.jinxAlbum)!.pngData()!
        playlist.imageData = imageData
        playlist.isCheckingForDuplicates = true
        return playlist
    }()
    
    static let playlist3: CDPlaylist = {
        let playlist = CDPlaylist(
            context: managedObjectContext
        )
        playlist.name = "Gizzard & The Lizard Wizard"
        let imageData = UIImage(.jinxAlbum)!.pngData()!
        playlist.imageData = imageData
        playlist.isCheckingForDuplicates = false
        playlist.didCheckForDuplicates = false
        return playlist
    }()
    
    static let managedObjectContext = NSManagedObjectContext(
        concurrencyType: .mainQueueConcurrencyType
    )
    
    static var previews: some View {
        List {
            PlaylistCellView(playlist: playlist)
            PlaylistCellView(playlist: playlist2)
            PlaylistCellView(playlist: playlist3)
        }
        .environmentObject(Spotify())
        .environment(\.managedObjectContext, managedObjectContext)
    }
}

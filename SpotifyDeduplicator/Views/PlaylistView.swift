import SwiftUI
import Combine
import CoreData

struct PlaylistView: View {
    
    @EnvironmentObject var spotify: Spotify
    @Environment(\.managedObjectContext) var managedObjectContext
    
    @State private var image = Image(.spotifyAlbumPlaceholder)
    @State private var cancellables: Set<AnyCancellable> = []
    
    @ObservedObject var playlist: CDPlaylist
    
    var body: some View {
        HStack {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 70)
                .cornerRadius(5)
            
            VStack {
                Text(playlist.name ?? "Unknown")
                    .font(.headline)
                Spacer()
            }
        }
        .padding(.vertical, 10)
        .onAppear(perform: loadImage)
        .onReceive(playlist.objectWillChange) { _ in
            self.loadImage()
        }
    }
    
    func loadImage() {
        
        if let imageData = playlist.imageData,
                // if the snapshot id has changed, then the playlist image
                // might have changed, so don't use the image saved in CoreData.
                playlist.snapshotId == playlist.lastImageRequestedSnapshotId {
            if let uiImage = UIImage(data: imageData) {
                Loggers.loadingImages.trace(
                    "found image in CoreData for \(playlist.name ?? "nil")"
                )
                self.image = Image(uiImage: uiImage)
            }
            else {
                Loggers.loadingImages.error(
                    "found imageData in CDPlaylist, " +
                    "but couldn't convert to Image"
                )
            }
            
            return
        }

        playlist.loadImage(spotify.api)
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
                    do {
                        if self.managedObjectContext.hasChanges {
                            try self.managedObjectContext.save()
                        }
                    } catch {
                        print("\(#function) line \(#line): couldn't save context")
                    }
                }
            )
            .store(in: &self.cancellables)
    }
    
}

struct PlaylistView_Previews: PreviewProvider {
    
    static let playlist: CDPlaylist = {
        let playlist = CDPlaylist(
            context: NSManagedObjectContext(
                concurrencyType: .mainQueueConcurrencyType
            )
        )
        playlist.name = "This is Jimi Hendrix"
        let imageData = UIImage(.jinxAlbum)!.pngData()!
        playlist.imageData = imageData
        return playlist
    }()
        
    static var previews: some View {
        List(0..<10) { _ in
            PlaylistView(playlist: playlist)
            // PlaylistView(playlist: .constant(playlist))
        }
    }
}

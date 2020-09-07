import Foundation
import SwiftUI
import Combine
import CoreData
import SpotifyWebAPI

@objc(CDPlaylist)
public class CDPlaylist: NSManagedObject {

    private var loadImagePublisher: AnyPublisher<Image, Error>? = nil
    
    /// Converts `imageData` to `Image`.
    var image: Image? {
        if let data = self.imageData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return nil
    }
    
    /// Sets `name`, `snapshotId`, and `uri`.
    func setFromPlaylist(_ playlist: Playlist<PlaylistsItemsReference>) {
        self.name = playlist.name
        self.snapshotId = playlist.snapshotId
        self.uri = playlist.uri
    }
    
    /// Loads the image using the URI of the playlist.
    /// If the image has already been saved to `imageData`,
    /// then this is returned instead and no network requests are made.
    func loadImage(
        _ spotify: SpotifyAPI<AuthorizationCodeFlowManager>
    ) -> AnyPublisher<Image, Error> {
        
        guard let playlistURI = self.uri else {
            return SpotifyLocalError.other("CDPlaylist URI was nil")
                .anyFailingPublisher(Image.self)
        }
        
        // if this method has already been called,
        // meaning an image is already being retreived from the web,
        // then return the same publisher instead of creating a new one,
        // ensuring that the image is only requested from the network once.
        if let loadImagePublisher = self.loadImagePublisher {
            Loggers.loadingImages.trace(
                "\nreturning previous loadImagePublisher for " +
                "\(self.name ?? "nil")\n"
            )
            return loadImagePublisher
        }
        
        Loggers.loadingImages.trace(
            "loading image for \(self.name ?? "nil")"
        )
        
        // the url for the playlist image is temporary,
        // so a request to the endpoint for playlist images
        // must be made everytime an image needs to be loaded.
        let loadImagePublisher = spotify.getPlaylistCoverImage(playlistURI)
            .tryMap { spotifyImages -> URL in
                // get the url for the largest image
                guard let imageURL = spotifyImages.largest?.url,
                        let url = URL(string: imageURL) else {
                    throw SpotifyLocalError.other(
                        "couldn't get image URL for \(self.name ?? "nil")"
                    )
                }
                return url
            }
            .flatMap { url in
                // retrieve the image from the url
                 URLSession.shared.dataTaskPublisher(for: url)
                    .mapError { $0 as Error }
            }
            // updating CoreData classes from a background thread
            // can cause a crash
            .receive(on: RunLoop.main)
            .tryMap { data, urlResponse -> Image in
                if let uiImage = UIImage(data: data) {
                    self.imageData = data
                    self.lastImageRequestedSnapshotId = self.snapshotId
                    Loggers.loadingImages.trace(
                        "finished loading image for \(self.name ?? "nil")"
                    )
                    return Image(uiImage: uiImage)
                }
                throw SpotifyLocalError.other(
                    "couldn't convert data to image"
                )
            }
            .handleEvents(receiveCompletion: { _ in
                self.loadImagePublisher = nil
            })
            // ensure only one network request is made even if there
            // are multiple subscribers.
            .share()
            .eraseToAnyPublisher()
        
        self.loadImagePublisher = loadImagePublisher
        return loadImagePublisher
        
    }
    
}

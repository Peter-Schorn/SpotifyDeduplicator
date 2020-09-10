import Foundation
import CoreData
import Combine
import SwiftUI
import SpotifyWebAPI

@objc(CDAlbum)
public class CDAlbum: NSManagedObject {

    private var loadImagePublisher: AnyPublisher<Image, Error>? = nil
    
    /// Converts `imageData` to `Image`.
    var image: Image? {
        if let data = self.imageData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return nil
    }
    
    /// Sets `name`, `uri`, and `imageURL`.
    func setFromAlbum(_ album: Album) {
        self.name = album.name
        self.uri = album.uri
        self.imageURL = album.images?.largest?.url
        
    }
    
    func loadImage(
        _ spotify: Spotify
    ) -> AnyPublisher<Image, Error> {
        
        guard let imageURL = self.imageURL,
                let url = URL(string: imageURL) else {
            return SpotifyLocalError.other(
                "CDAlbum imageURL was nil or couldn't convert to URL"
            )
            .anyFailingPublisher(Image.self)
        }
     
        if let loadImagePublisher = self.loadImagePublisher {
            return loadImagePublisher
        }
        
        let loadImagePublisher = URLSession.shared.dataTaskPublisher(
            for: url
        )
        .receive(on: RunLoop.main)
        .tryMap { data, urlResponse -> Image in
            if let uiImage = UIImage(data: data) {
                self.imageData = data
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
            // ensure a subscriber does not receive a publisher
            // that has already completed.
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

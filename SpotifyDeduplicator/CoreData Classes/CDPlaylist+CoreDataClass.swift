import Foundation
import SwiftUI
import Combine
import CoreData
import SpotifyWebAPI

@objc(CDPlaylist)
public class CDPlaylist: NSManagedObject {

    private var deDuplicateCancellables: Set<AnyCancellable> = []
    
    private var loadImagePublisher: AnyPublisher<Image, Error>? = nil
    
    var isDeduplicating = false
    var isCheckingForDuplicates = false
    var didCheckForDuplicates = false
    
    var finishedCheckingForDuplicates = PassthroughSubject<Void, Never>()
    var finishedDeDuplicating = PassthroughSubject<Void, Never>()
    
    /// `index` is the index of the item in the playlist.
    var duplicatePlaylistItems: [(PlaylistItem, index: Int)] = []
    
    /// Equivalent to `duplicatePlaylistItems.count`.
    var duplicatesCount: Int {
        return duplicatePlaylistItems.count
    }
    
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
    func loadImage(
        _ spotify: Spotify
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
        let loadImagePublisher = spotify.api.getPlaylistCoverImage(playlistURI)
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
    
    /// Checks for duplicate items in the playlist.
    func checkForDuplicates(
        _ spotify: Spotify
    ) -> AnyCancellable? {
    
        guard let uri = self.uri else {
            Loggers.cdPlaylist.error(
                "URI was nil for \(self.name ?? "nil")"
            )
            return nil
        }
        
        self.duplicatePlaylistItems = []
        self.isCheckingForDuplicates = true
        self.objectWillChange.send()
        
        Loggers.cdPlaylist.trace(
            "checking for duplicates for \(self.name ?? "nil")"
        )
        
        return spotify.api.playlistItems(uri)
            .extendPages(spotify.api)
            .collect()
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    Loggers.playlistView.trace(
                        "spotify.api.playlistItems completion for " +
                        "\(self.name ?? "nil"): \(completion)"
                    )
                    if case .failure(_) = completion {
                        self.didCheckForDuplicates = true
                        self.isCheckingForDuplicates = false
                        self.objectWillChange.send()
                    }
                },
                receiveValue: receivePlaylistItems(_:)
            )
            
        
    }
    
    private func receivePlaylistItems(
        _ playlistItemsArray: [PlaylistItems]
    ) {
        
        let playlistItems = playlistItemsArray
            .flatMap(\.items)
            .map(\.item)
        
        var seenPlaylists: Set<PlaylistItem> = []
        
        for (index, playlistItem) in playlistItems.enumerated() {
            
            if case .track(let track) = playlistItem {
                if track.isLocal { continue }
            }
            
            for seenPlaylist in seenPlaylists {
                if playlistItem.isProbablyTheSameAs(seenPlaylist) {
                    self.duplicatePlaylistItems.append(
                        (playlistItem, index: index)
                    )
                    self.objectWillChange.send()
                }
            }
            seenPlaylists.insert(playlistItem)
            
        }
        Loggers.cdPlaylist.trace(
            "finished checking for duplicates for \(self.name ?? "nil")"
        )
        self.didCheckForDuplicates = true
        self.isCheckingForDuplicates = false
        self.finishedCheckingForDuplicates.send()
        self.objectWillChange.send()

    }
    
    
    func deDuplicate(_ spotify: Spotify) {
        
        if duplicatePlaylistItems.isEmpty {
            return
        }
        
        guard let playlistURI = self.uri else {
            Loggers.cdPlaylist.error(
                "missing URI for \(self.name ?? "nil")"
            )
            return
        }
        
        self.deDuplicateCancellables.cancellAll()
        self.isDeduplicating = true
        self.objectWillChange.send()
        
        DispatchQueue.global(qos: .userInteractive).async {
            
            let duplicateItems = self.duplicatePlaylistItems
                .sorted { lhs, rhs in
                    return lhs.index > rhs.index
                }
            
            Loggers.cdPlaylist.trace(
                "removing \(duplicateItems.count) duplicate items for " +
                "\(self.name ?? "nil")"
            )
            
            let semaphore = DispatchSemaphore(value: 1)
            
            let chunkedItemsArray = duplicateItems.chunked(size: 100)
            for (index, chunkedItems) in chunkedItemsArray.enumerated() {
                
                let urisWithPositionsDict: [String: [Int]] = chunkedItems.reduce(
                    into: [:]
                ) { dictionary, playlistItem in
                    guard let uri = playlistItem.0.uri else { return }
                    dictionary[uri, default: []].append(playlistItem.index)
                }
                
                let urisWithPositions: [URIWithPositions] = urisWithPositionsDict.reduce(
                    into: []
                ) { urisWithPositions, nextItem in
                    urisWithPositions.append(
                        .init(uri: nextItem.key, positions: nextItem.value)
                    )
                }
                
                let urisWithPositionsContainer = URIsWithPositionsContainer(
                    snapshotId: nil, urisWithPositions: urisWithPositions
                )
                
                semaphore.wait()
                
                spotify.api.removeSpecificOccurencesFromPlaylist(
                    playlistURI, of: urisWithPositionsContainer
                )
                .sink(
                    receiveCompletion: { completion in
                        Loggers.deDuplicateView.trace(
                            "completion for \(self.name ?? "nil"): " +
                            "\(completion)"
                        )
                        semaphore.signal()
                        if index == chunkedItemsArray.count - 1 {
                            DispatchQueue.main.async {
                                Loggers.deDuplicateView.trace(
                                    "finished removing all duplicates for: " +
                                    "\(self.name ?? "nil")"
                                )
                                self.duplicatePlaylistItems = []
                                self.isDeduplicating = false
                                self.finishedDeDuplicating.send()
                                self.objectWillChange.send()
                            }
                        }
                    },
                    receiveValue: { _ in }
                )
                .store(in: &self.deDuplicateCancellables)
                

            }
            
                
        }

    }
    
    
}

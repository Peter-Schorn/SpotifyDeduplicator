import Foundation
import SwiftUI
import Combine
import CoreData
import SpotifyWebAPI

@objc(CDPlaylist)
public class CDPlaylist: NSManagedObject {

    static var managedObjectContext: NSManagedObjectContext {
        return (UIApplication.shared.delegate as! AppDelegate)
                .persistentContainer.viewContext
    }
    
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
    
//    var albumsArray: [CDAlbum] {
//        let
//    }
    
    /// Sets `name`, `snapshotId`, `uri`, and `tracksCount`.
    func setFromPlaylist(_ playlist: Playlist<PlaylistsItemsReference>) {
        self.name = playlist.name
        self.snapshotId = playlist.snapshotId
        self.uri = playlist.uri
        self.tracksCount = Int64(playlist.items.total)
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
                    if case .finished = completion {
                        self.didCheckForDuplicates = true
                    }
                    self.isCheckingForDuplicates = false
                    self.finishedCheckingForDuplicates.send()
                    self.objectWillChange.send()
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
        
        self.retreiveAlbums()

    }
    
    /// Retrieve the albums for all of the duplicate items.
    func retreiveAlbums() {
        
        Loggers.cdPlaylistAlbums.trace(
            "retrieving albums for \(self.name ?? "nil")"
        )
        
        var allDuplicateAlbumURIs: Set<String> = []
        for playlistItem in duplicatePlaylistItems.map(\.0) {
            
            let uri: String?
            let albumName: String?
            let albumImageURL: String?
            switch playlistItem {
                case .track(let track):
                    uri = track.album?.uri
                    albumName = track.album?.name
                    albumImageURL = track.album?.images?.smallest?.url
                case .episode(let episode):
                    uri = episode.show?.uri
                    albumName = episode.show?.name
                    albumImageURL = episode.show?.images?.smallest?.url
            }
            
            guard let albumURI = uri else {
                continue
            }
            
            if !allDuplicateAlbumURIs.insert(albumURI).inserted {
                // the album has already been retrieved in this execution
                // context, but has not necessarily been saved to the store
                // yet.
                continue
            }
            
            if let albums = self.albums as? Set<CDAlbum> {
                if albums.contains(where: { album in
                    album.uri == albumURI
                }) {
                    // the album has already been saved to core data
                    continue
                }
            }
            
            Loggers.cdPlaylistAlbums.trace(
                "new album \(albumName ?? "nil") for \(self.name ?? "nil")"
            )
            
            let cdAlbum = CDAlbum(context: Self.managedObjectContext)
            cdAlbum.uri = albumURI
            cdAlbum.name = albumName
            cdAlbum.imageURL = albumImageURL
            
        }
        
        Loggers.cdPlaylistAlbums.trace(
            "retrieved \(allDuplicateAlbumURIs.count) albums " +
            "for \(self.name ?? "nil")"
        )
        
        if let albums = self.albums as! Set<CDAlbum>? {
            // remove albums from core data that are no longer
            // associated with the duplicate items.
            for album in albums {
                guard let albumURI = album.uri else { continue }
                if !allDuplicateAlbumURIs.contains(albumURI) {
                    Self.managedObjectContext.delete(album)
                    Loggers.cdPlaylistAlbums.trace(
                        "removed album \(album.name ?? "nil") " +
                        "for \(self.name ?? "nil")"
                    )
                }
            }
        }
        
        if Self.managedObjectContext.hasChanges {
            do {
                try Self.managedObjectContext.save()
                
            } catch {
                Loggers.cdPlaylistAlbums.error(
                    "couldn't saved context after updating album:\n\(error)"
                )
            }
        }
        
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

            Loggers.cdPlaylist.trace(
                "removing \(self.duplicatePlaylistItems.count) " +
                "duplicate items for  \(self.name ?? "nil")"
            )
            
            let duplicateItems = self.duplicatePlaylistItems
                .sorted { lhs, rhs in
                    return lhs.index > rhs.index
                }
            
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

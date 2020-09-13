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
    private var reloadPlaylistCancellables: Set<AnyCancellable> = []
    
    private var loadImagePublisher: AnyPublisher<Image, Error>? = nil

    var lastCheckedForDuplicatesSnapshotId: String? = nil
    
    var isReloading = false
    var isDeduplicating = false
    var isCheckingForDuplicates = false
    var didCheckForDuplicates = false
    
    /// `index` is the index of the item in the playlist.
    var duplicatePlaylistItems: [(PlaylistItem, index: Int)] = [] {
        didSet {
            duplicatesCount = Int64(duplicatePlaylistItems.count)
        }
    }
    
    /// Converts `imageData` to `Image`.
    var image: Image? {
        if let data = self.imageData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return nil
    }
    
    /// Sets `name`, `snapshotId`, `uri`, and `itemsCount`.
    func setFromPlaylist(_ playlist: Playlist<PlaylistsItemsReference>) {
        self.name = playlist.name
        self.snapshotId = playlist.snapshotId
        self.uri = playlist.uri
        self.itemsCount = Int64(playlist.items.total)
    }
    
    func setFromPlaylist(_ playlist: Playlist<PlaylistItems>) {
        self.name = playlist.name
        self.snapshotId = playlist.snapshotId
        self.uri = playlist.uri
        self.itemsCount = Int64(playlist.items.total)
    }

    /// Loads the image using the URI of the playlist.
    func loadImage(
        _ spotify: Spotify
    ) -> AnyPublisher<Image, Error> {
        
        guard let playlistURI = self.uri else {
            return SpotifyLocalError.other("CDPlaylist URI was nil")
                .anyFailingPublisher(Image.self)
        }
        
        // If this method has already been called, meaning an image is already
        // being retreived from the web, then return the same publisher instead
        // of creating a new one, ensuring that the image is only requested from
        // the network once.
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
    
    func reload(_ spotify: Spotify) {
        self.reloadPlaylistCancellables.cancellAll()
        guard let uri = self.uri else {
            spotify.alertTitle = "Couldn't Reload Playlist"
            spotify.alertMessage = "Missing Data"
            spotify.alertIsPresented = true
            return
        }
        self.isReloading = true
        self.objectWillChange.send()
        spotify.api.playlist(uri)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        spotify.alertTitle = "Couldn't Reload Playlist"
                        spotify.alertMessage = error.localizedDescription
                        spotify.alertIsPresented = true
                    }
                    self.isReloading = false
                    self.objectWillChange.send()
                },
                receiveValue: { playlist in
                    if playlist.snapshotId !=
                            self.lastCheckedForDuplicatesSnapshotId {
                        self.setFromPlaylist(playlist)
                        self.checkForDuplicates(spotify)?
                            .sink(receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    spotify.alertTitle = "Couldn't Get Duplicates"
                                    spotify.alertMessage = error.localizedDescription
                                    spotify.alertIsPresented = true
                                }
                            })
                            .store(in: &self.reloadPlaylistCancellables)
                    }
                    else {
                        Loggers.cdPlaylist.trace(
                            "no need to check for duplicates for " +
                            "\(self.name ?? "nil")"
                        )
                    }
                    self.objectWillChange.send()
                }
            )
            .store(in: &self.reloadPlaylistCancellables)
            
    }
    
    /// Checks for duplicate items in the playlist.
    func checkForDuplicates(
        _ spotify: Spotify
    ) -> AnyPublisher<Void, Error>? {
    
        Loggers.cdPlaylist.trace(
            """
            \(self.name ?? "nil"): snapshotId: '\(snapshotId ?? "nil")' \
            lastDeDuplicatedSnapshotId: '\(lastDeDuplicatedSnapshotId ?? "nil")'
            """
        )
        if snapshotId != nil && [
            lastDeDuplicatedSnapshotId, lastCheckedForDuplicatesSnapshotId
        ].contains(snapshotId) {
            // No need to check the playlist for duplicates; the snapshot id
            // hasn't changed since the last time duplicates were removed from
            // the playlist or since the playlist was checked for duplicates.
            // The snapshot id is a version identifier for the playlist.
            // Everytime the playlist changes, the snapshot id changes.
            Loggers.cdPlaylist.trace(
                """
                \(self.name ?? "nil") \
                snapshotId == lastDeDuplicatedSnapshotId: \
                \(snapshotId == lastDeDuplicatedSnapshotId)
                snapshotId == lastCheckedForDuplicatesSnapshotId: \
                \(snapshotId == lastCheckedForDuplicatesSnapshotId)
                """
            )
            self.didCheckForDuplicates = true
            self.objectWillChange.send()
            return nil
        }
        
        guard spotify.isAuthorized else {
            Loggers.cdPlaylist.warning(
                "Unauthorized for \(self.name ?? "nil")"
            )
            return nil
        }
        
        guard let uri = self.uri else {
            Loggers.cdPlaylist.error(
                "URI was nil for \(self.name ?? "nil")"
            )
            return nil
        }
        
        self.isCheckingForDuplicates = true
        self.objectWillChange.send()
        
        Loggers.cdPlaylistTimeProfiler.trace(
            "\(self.name ?? "nil"): spotify.api.playlistItems(uri): " +
            "\(Date().timeIntervalSinceReferenceDate)"
        )
        return spotify.api.playlistItems(uri)
            .extendPages(spotify.api)
            .handleEvents(receiveOutput: { playlistItems in
                Loggers.cdPlaylistTimeProfiler.trace(
                    "page at offset \(playlistItems.offset)"
                )
            })
            .collect()
            // intentionally throw an error for debugging purposes
//            .tryMap { upstream in
//                if Int.random(in: 1...5) == 1 {
//                    throw SpotifyLocalError.other(
//                        "Intentional Error for \(self.name ?? "nil")"
//                    )
//                }
//                return upstream
//            }
            .handleEvents(receiveCompletion: { completion in
                if case .failure(_) = completion {
                    DispatchQueue.main.async {
                        self.isCheckingForDuplicates = false
                        self.objectWillChange.send()
                    }
                }
            })
            .map(receivePlaylistItems(_:))
            .eraseToAnyPublisher()

        
    }
    
    private func receivePlaylistItems(
        _ playlistItemsArray: [PlaylistItems]
    ) {
        
        // this section of code is very performance-sensitive
        DispatchQueue.global(qos: .userInitiated).async {
            
            Loggers.cdPlaylistTimeProfiler.trace(
                "\(self.name ?? "nil"): \(playlistItemsArray.count): " +
                "\(Date().timeIntervalSinceReferenceDate)"
            )
            
            let playlistItems = playlistItemsArray
                .flatMap(\.items)
                .map(\.item)
            
            Loggers.cdPlaylistTimeProfiler.trace(
                "\(self.name ?? "nil"): \(playlistItems.count): " +
                "\(Date().timeIntervalSinceReferenceDate)"
            )
            
            DispatchQueue.main.sync {
                Loggers.cdPlaylist.trace(
                    "self.duplicatePlaylistItems = []"
                )
                self.duplicatePlaylistItems = []
            }
            
            var seenPlaylists: Set<PlaylistItem> = []
            var duplicatePlaylistItemsLocalCopy = self.duplicatePlaylistItems
            for (index, playlistItem) in playlistItems.enumerated() {
                
                if case .track(let track) = playlistItem {
                    if track.isLocal { continue }
                }
               
                for seenPlaylist in seenPlaylists {
                    if playlistItem.isProbablyTheSameAs(seenPlaylist) {
                        duplicatePlaylistItemsLocalCopy.append(
                            (playlistItem, index: index)
                        )
                    }
                }
                seenPlaylists.insert(playlistItem)
                
            }
            Loggers.cdPlaylistTimeProfiler.trace(
                "finished checking for duplicates for \(self.name ?? "nil"): " +
                "\(Date().timeIntervalSinceReferenceDate)"
            )
        
            DispatchQueue.main.async {
                self.duplicatePlaylistItems = duplicatePlaylistItemsLocalCopy
                self.didCheckForDuplicates = true
                self.isCheckingForDuplicates = false
                self.lastCheckedForDuplicatesSnapshotId = self.snapshotId
                if self.duplicatesCount == 0 {
                    self.lastDeDuplicatedSnapshotId = self.snapshotId
                }
                self.objectWillChange.send()
                self.retreiveAlbums()
            }
        }
        
    }
    
    /// Retrieve the albums for all of the duplicate items.
    func retreiveAlbums() {
        
        Loggers.cdPlaylistTimeProfiler.trace(
            "retrieving albums for \(self.name ?? "nil"): " +
            "\(Date().timeIntervalSinceReferenceDate)"
        )
        
        var allAlbumURIs: Set<String> = []
        for playlistItem in self.duplicatePlaylistItems.map(\.0) {
            
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
            
            if !allAlbumURIs.insert(albumURI).inserted {
                // The album has already been retrieved within this method
                // but has not necessarily been saved to the store yet.
                continue
            }
            
            if let albums = self.albums as? Set<CDAlbum> {
                if albums.contains(where: { album in
                    album.uri == albumURI
                }) {
                    // the album has already been saved to the store
                    continue
                }
            }
            
            let cdAlbum = CDAlbum(context: Self.managedObjectContext)
            cdAlbum.uri = albumURI
            cdAlbum.name = albumName
            cdAlbum.imageURL = albumImageURL
            
        }
        
        Loggers.cdPlaylistTimeProfiler.trace(
            "retrieved \(allAlbumURIs.count) albums " +
            "for \(self.name ?? "nil"): " +
            "\(Date().timeIntervalSinceReferenceDate)"
        )
        
        if let albums = self.albums as! Set<CDAlbum>? {
            // remove albums from core data that are no longer
            // associated with the duplicate items.
            for album in albums {
                guard let albumURI = album.uri else { continue }
                if !allAlbumURIs.contains(albumURI) {
                    Self.managedObjectContext.delete(album)
                    Loggers.cdPlaylistTimeProfiler.trace(
                        "removed album \(album.name ?? "nil") " +
                        "for \(self.name ?? "nil"): " +
                        "\(Date().timeIntervalSinceReferenceDate)"
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
        
        Loggers.cdPlaylistTimeProfiler.trace(
            "finished retrieving albums for \(self.name ?? "nil"): " +
            "\(Date().timeIntervalSinceReferenceDate)"
        )
        
    }
    
    /// Remove all of the duplicate items from Spotify
    func deDuplicate(_ spotify: Spotify) -> AnyPublisher<Void, Error>? {
        
        if duplicatePlaylistItems.isEmpty || !spotify.isAuthorized {
            return nil
        }
        
        guard let playlistURI = self.uri else {
            Loggers.cdPlaylist.error(
                "missing URI for \(self.name ?? "nil")"
            )
            return nil
        }
        
        let finishedDeDuplicatingSubject = PassthroughSubject<Void, Error>()
        
        self.deDuplicateCancellables.cancellAll()
        self.isDeduplicating = true
        self.objectWillChange.send()
        
        var duplicateError: Error? = nil
        
        DispatchQueue.global(qos: .userInteractive).async {

            Loggers.cdPlaylist.trace(
                "removing \(self.duplicatePlaylistItems.count) " +
                "duplicate items for  \(self.name ?? "nil"); " +
                "itemsCount: \(self.itemsCount)"
            )
            
            let duplicateItems = self.duplicatePlaylistItems
                .sorted { lhs, rhs in
                    return lhs.index > rhs.index
                }
            
            let semaphore = DispatchSemaphore(value: 1)
            
            let chunkedItemsArray = duplicateItems.chunked(size: 100)
            for (index, chunkedItems) in chunkedItemsArray.enumerated() {
                
                let urisWithPositionsContainer =
                        URIsWithPositionsContainer(chunkedItems)
                
                semaphore.wait()
                
                spotify.api.removeSpecificOccurencesFromPlaylist(
                    playlistURI, of: urisWithPositionsContainer
                )
                .receive(on: RunLoop.main)
                .sink(
                    receiveCompletion: { completion in
                        Loggers.deDuplicateView.trace(
                            "completion for \(self.name ?? "nil"): " +
                            "\(completion)"
                        )
                        if case .failure(let error) = completion {
                            self.lastDeDuplicatedSnapshotId = nil
                            duplicateError = error
                        }
                        
                        semaphore.signal()
                        
                        if index == chunkedItemsArray.count - 1 {
                            // then we've finished removing duplicates
                            Loggers.cdPlaylist.trace(
                                "finished removing all duplicates for: " +
                                "\(self.name ?? "nil")"
                            )
                            self.isDeduplicating = false
                            if let error = duplicateError {
                                finishedDeDuplicatingSubject.send(
                                    completion: .failure(error)
                                )
                            }
                            else {
                                finishedDeDuplicatingSubject.send(
                                    completion: .finished
                                )
                            }
                            self.objectWillChange.send()
                        }
                    },
                    receiveValue: { snapshotId in
                        self.duplicatePlaylistItems.removeAll { playlistItem in
                            chunkedItems.contains(where: { $0 == playlistItem })
                        }
                        self.itemsCount -= Int64(chunkedItems.count)
                        Loggers.cdPlaylistAlbums.trace(
                            "\(self.name ?? "nil"): itemsCount: \(self.itemsCount): " +
                            "chunkedItems.count: \(chunkedItems.count)"
                        )
                        
                        guard index == chunkedItemsArray.count - 1 else {
                            return
                        }
                        self.lastDeDuplicatedSnapshotId = snapshotId
                        self.snapshotId = snapshotId
                        if Self.managedObjectContext.hasChanges {
                            do {
                                try Self.managedObjectContext.save()
                                
                            } catch {
                                Loggers.cdPlaylistAlbums.error(
                                    "couldn't save context:\n\(error)"
                                )
                            }
                        }
                    }
                )
                .store(in: &self.deDuplicateCancellables)

            }
            
        }

        Loggers.cdPlaylist.trace("return finishedDeDuplicatingSubject")
        return finishedDeDuplicatingSubject
            .eraseToAnyPublisher()
    }
    
}

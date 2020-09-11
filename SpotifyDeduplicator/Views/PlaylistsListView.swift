import SwiftUI
import Combine
import CoreData
import SpotifyWebAPI

struct PlaylistsListView: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @Environment(\.colorScheme) var colorScheme

    @EnvironmentObject var spotify: Spotify
    
    @FetchRequest(
        entity: CDPlaylist.entity(),
        sortDescriptors: [
            .init(keyPath: \CDPlaylist.index, ascending: true)
        ]
    ) var savedPlaylists: FetchedResults<CDPlaylist>
    
    @FetchRequest(
        entity: CDPlaylist.entity(),
        sortDescriptors: [
            .init(keyPath: \CDPlaylist.duplicatesCount, ascending: false)
        ],
        predicate: .init(format: "duplicatesCount > 0")
        
    ) var filteredPlaylists: FetchedResults<CDPlaylist>
    
    @State private var didRequestPlaylists = false
    @State private var processingPlaylistsCount = 0
    @State private var couldntLoadPlaylists = false
    
    // MARK: Cancellables
    @State private var didAuthorizeCancellable: AnyCancellable? = nil
    @State private var didRefreshCancellable: AnyCancellable? = nil
    @State private var retrievePlaylistsCancellable: AnyCancellable? = nil
    @State private var checkForDuplicatesCancellables:
            Set<AnyCancellable> = []

    var body: some View {
        ZStack {
            if savedPlaylists.isEmpty {
                if spotify.isLoadingPlaylists {
                    HStack {
                        ActivityIndicator(
                            isAnimating: .constant(true),
                            style: .large
                        )
                            .scaleEffect(0.8)
                        Text("Retrieving Playlists")
                            .lightSecondaryTitle()
                    }
                }
                else if couldntLoadPlaylists {
                    Text("Couldn't Load Playlists")
                        .lightSecondaryTitle()
                }
                else if self.spotify.isAuthorized {
                    Text("No Playlists Found")
                        .lightSecondaryTitle()
                }
            }
            else if !spotify.isSortingByIndex &&
                    filteredPlaylists.isEmpty &&
                    self.spotify.isAuthorized {
                Text("No Playlists With Duplicates")
                    .lightSecondaryTitle()
            }
            else {
                List {
                    ForEach(playlists, id: \.self) { playlist in
                        PlaylistCellView(playlist: playlist)
                    }
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 50)
                }
                VStack {
                    Spacer()
                    DeDuplicateView(
                        processingPlaylistsCount: $processingPlaylistsCount
                    )
                    .padding(.bottom, 15)
                }
            }
        }
        .alert(isPresented: $spotify.alertIsPresented) {
            Alert(
                title: Text(spotify.alertTitle),
                message: Text(spotify.alertMessage)
            )
        }
        .onAppear {
            UITableView.appearance().separatorStyle = .none
            self.setupSubscriptions()
        }
    }
    
    var playlists: FetchedResults<CDPlaylist> {
        if spotify.isSortingByIndex {
            return savedPlaylists
        }
        return filteredPlaylists
    }
    
    func retrievePlaylistsFromSpotify() {
        
        Loggers.playlistsListView.notice(
            "isAuthorized: \(spotify.isAuthorized)"
        )
        
        self.checkForDuplicatesCancellables.cancellAll()
        
        self.processingPlaylistsCount = 0
        for playlist in savedPlaylists {
            playlist.isCheckingForDuplicates = false
        }
        
        if !spotify.isAuthorized {
            Loggers.playlistsListView.error(
                "tried to retrieve playlists without authorization"
            )
            return
        }
        
        var allUserPlaylistURIs: Set<String> = []
        
        self.spotify.isLoadingPlaylists = true
        self.retrievePlaylistsCancellable = spotify.getCurrentUserId()
            .flatMap { _ in
                self.spotify.api.currentUserPlaylists()
            }
            .extendPages(spotify.api)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    self.spotify.isLoadingPlaylists = false
                    switch completion {
                        case .finished:
                            Loggers.playlistsListView.trace(
                                "currentUserPlaylists finished successfully"
                            )
                            self.couldntLoadPlaylists = false
                        case .failure(let error):
                            Loggers.playlistsListView.error(
                                "couldn't load playlists:\n\(error)"
                            )
                            self.couldntLoadPlaylists = true
                            self.spotify.alertTitle = "Couldn't Load Playlists"
                            self.spotify.alertMessage = error
                                    .localizedDescription
                            self.spotify.alertIsPresented = true
                    }
                    self.removeUnfollowedPlaylists(allUserPlaylistURIs)
                    
                },
                receiveValue: { playlists in
                    for uri in playlists.items.map(\.uri) {
                        allUserPlaylistURIs.insert(uri)
                    }
                    self.receivePlaylists(playlists)
                }
            )
              
    }
    
    func receivePlaylists(
        _ playlists: PagingObject<Playlist<PlaylistsItemsReference>>
    ) {
        
        Loggers.playlistsListView.trace(
            "received \(playlists.items.count) playlists"
        )
        
        for (index, playlist) in playlists.items.enumerated() {
            
            guard spotify.isAuthorized else { return }
            
            // skip playlists that aren't owned by the user
            // because they can't be modified.
            guard playlist.owner?.id == self.spotify
                .keychain[string: KeychainKeys.userId] else {
                    continue
            }
            
            let cdPlaylist: CDPlaylist
            
            // if the playlist already exists in the
            // persistent store, then use that.
            if let savedPlaylist = self.savedPlaylists
                .first(where: { savedPlaylist in
                    savedPlaylist.uri == playlist.uri
            }) {
                cdPlaylist = savedPlaylist
                Loggers.playlistsListView.trace(
                    "already in store: \(playlist.name)"
                )
            }
            // else, create a new cdPlaylist.
            else {
                cdPlaylist = CDPlaylist(
                    context: self.managedObjectContext
                )
                Loggers.playlistsListView.trace(
                    "ADDING to store: \(playlist.name)"
                )
            }
            
            // update the playlist information in the persistent store
            if let cdPlaylistName = cdPlaylist.name {
                if playlist.name != cdPlaylist.name {
                    Loggers.playlistsListView.notice(
                        "\(playlist.name) != \(cdPlaylistName)"
                    )
                }
            }
            cdPlaylist.setFromPlaylist(playlist)
            
            /*
             The index of the playlist as returned from the
             `currentUserPlaylists` endpoint. Interestingly,
             this always matches the order that the playlists are
             displayed in the sidebar of the desktop client; if you
             drag to reorder them, then this immediately affects the
             order that the API returns them in.
             */
            cdPlaylist.index = Int64(index + playlists.offset)
            cdPlaylist.objectWillChange.send()
            
            Loggers.playlistsListView.trace(
                "checking for duplicates for \(cdPlaylist.name ?? "nil")"
            )
            if let publisher = cdPlaylist.checkForDuplicates(spotify) {
                self.processingPlaylistsCount += 1
                
                publisher
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { _ in
                        self.processingPlaylistsCount -= 1
                        Loggers.playlistsListView.trace(
                            """
                            finishedCheckingForDuplicates for \(cdPlaylist.name ?? "nil");
                            count: \(self.processingPlaylistsCount)
                            """
                        )
                    })
                    .store(in: &checkForDuplicatesCancellables)
            
            }
            
            
        }  // end for playlist in playlists
        
        if managedObjectContext.hasChanges {
            do {
                try self.managedObjectContext.save()
                
            } catch {
                Loggers.playlistsListView.error(
                    "couldn't save context:\n\(error)"
                )
            }
        }
        
    }
    
    /// Removes playlists from CoreData that the user unfollowed from Spotify.
    func removeUnfollowedPlaylists(_ allUserPlaylistURIs: Set<String>) {
        for savedPlaylist in self.savedPlaylists {
            guard let savedPlaylistURI = savedPlaylist.uri else {
                continue
            }
            if !allUserPlaylistURIs.contains(savedPlaylistURI) {
                self.managedObjectContext.delete(savedPlaylist)
                Loggers.playlistsListView.trace(
                    "removed playlist from core data: " +
                    (savedPlaylist.name ?? "nil")
                )
            }
        }
    }
    
    /// The refresh button in the navigation bar was pressed.
    func didPressRefresh() {
        Loggers.playlistsListView.trace("")
        self.retrievePlaylistsFromSpotify()
    }
    
    func setupSubscriptions() {
        subscribeToIsAuthorizedPublisher()
        self.didRefreshCancellable = spotify.didPressRefreshSubject
            .receive(on: RunLoop.main)
            .sink(receiveValue: didPressRefresh)
    }
    
    func subscribeToIsAuthorizedPublisher() {
        Loggers.playlistsListView.trace("")
        self.didAuthorizeCancellable = self.spotify.$isAuthorized
            .receive(on: RunLoop.main)
            .sink { isAuthorized in
                Loggers.playlistsListView.trace(
                    "spotify.$isAuthorized: \(isAuthorized)"
                )
                if isAuthorized {
                    if self.didRequestPlaylists { return }
                    self.didRequestPlaylists = true
                    self.retrievePlaylistsFromSpotify()
                }
                else {
                    self.didRequestPlaylists = false
                    self.processingPlaylistsCount = 0
                    self.checkForDuplicatesCancellables.cancellAll()
                    for playlist in self.savedPlaylists {
                        self.managedObjectContext.delete(playlist)
                    }
                    if self.managedObjectContext.hasChanges {
                        do {
                            try self.managedObjectContext.save()
        
                        } catch {
                            Loggers.playlistsListView.error(
                                "couldn't save context:\n\(error)"
                            )
                        }
                    }
                }
        }
        
    }
    
}

//struct PlaylistsView_Previews: PreviewProvider {
//    static var previews: some View {
//        PlaylistsListView()
//    }
//}


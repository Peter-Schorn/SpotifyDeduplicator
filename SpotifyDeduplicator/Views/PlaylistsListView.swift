import SwiftUI
import Combine
import SpotifyWebAPI

struct PlaylistsListView: View {
    
    @EnvironmentObject var spotify: Spotify

    @Environment(\.managedObjectContext) var managedObjectContext
    
    @FetchRequest(
        entity: CDPlaylist.entity(),
        sortDescriptors: [
            .init(keyPath: \CDPlaylist.index, ascending: true)
        ]
    ) var savedPlaylists: FetchedResults<CDPlaylist>

    @State private var cancellables: Set<AnyCancellable> = []
    
    @State private var couldntLoadPlaylists = false
    @State private var loadingPlaylists = false
    
    var body: some View {
        ZStack {
            if savedPlaylists.isEmpty {
                if loadingPlaylists {
                    ActivityIndicator(
                        isAnimating: .constant(true),
                        style: .large
                    )
                }
                else if couldntLoadPlaylists {
                    Text("Couldn't Load Playlists")
                        .font(.title)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                }
                else {
                    Text("No Playlists Found")
                        .font(.title)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                }
            }
            else {
                List(savedPlaylists, id: \.self) { playlist in
                    PlaylistView(playlist: playlist)
                }
                .padding(.bottom, 40)
                VStack {
                    Spacer()
                    DeDuplicateView()
                }
            }
        }
        .onAppear(perform: setupSubscriptions)
    }
    
    func retrievePlaylistsFromSpotify() {

        spotify.getCurrentUserId()
            .flatMap { _ in
                self.spotify.api.currentUserPlaylists()
            }
            .extendPages(spotify.api)
            // .tryMap { _ in
            //     throw SpotifyLocalError.other("intentional error")
            // }
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    self.loadingPlaylists = false
                    switch completion {
                        case .finished:
                            self.couldntLoadPlaylists = false
                        case .failure(let error):
                            Loggers.playlistsListView.error(
                                "couldn't load playlists:\n\(error)"
                            )
                            self.couldntLoadPlaylists = true
                        
                    }
                },
                receiveValue: receivePlaylists(_:)
            )
            .store(in: &cancellables)
              
    }
    
    func receivePlaylists(
        _ playlists: PagingObject<Playlist<PlaylistsItemsReference>>
    ) {
        
        for (index, playlist) in playlists.items.enumerated() {
            
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
                    print("\(playlist.name) != \(cdPlaylistName)")
                }
            }
            cdPlaylist.setFromPlaylist(playlist)
            print(
                "name after cdPlaylist.setFromPlaylist: " +
                "\(cdPlaylist.name ?? "nil")"
            )
            
            /*
             The index of the playlist as returned from the
             `currentUserPlaylists` endpoint. Interestingly,
             this always matches the order that the playlists are
             displayed in the sidebar of the desktop client; if you
             drag to reorder them, then this immediately affects the
             order that the API returns them in.
             */
            cdPlaylist.index = Int64(index + playlists.offset)
        }
        
        do {
            try self.managedObjectContext.save()
            
        } catch {
            Loggers.playlistsListView.error(
                "couldn't save context:\n\(error)"
            )
        }
        
    }
    
    /// The refresh button in the navigation bar was pressed.
    func didPressRefresh() {
        Loggers.playlistsListView.trace("")
        self.retrievePlaylistsFromSpotify()
    }
    
    func setupSubscriptions() {
        subscribeToIsAuthorizedPublisher()
        spotify.didPressRefreshSubject
            .receive(on: RunLoop.main)
            .sink(receiveValue: didPressRefresh)
            .store(in: &cancellables)
    }
    
    func subscribeToIsAuthorizedPublisher() {
        Loggers.playlistsListView.trace("")
        self.spotify.$isAuthorized
            .receive(on: RunLoop.main)
            .sink { isAuthorized in
                Loggers.playlistsListView.trace(
                    "$isAuthorized sink isAuthorized: \(isAuthorized)"
                )
                if isAuthorized {
                    self.loadingPlaylists = true
                    self.retrievePlaylistsFromSpotify()
                }
                else {
                    for playlist in self.savedPlaylists {
                        self.managedObjectContext.delete(playlist)
                    }
                    do {
                        try self.managedObjectContext.save()
                        
                    } catch {
                        Loggers.playlistsListView.error(
                            "couldn't save context:\n\(error)"
                        )
                    }
                }
            }
            .store(in: &cancellables)
    }
    
}

struct PlaylistsView_Previews: PreviewProvider {
    static var previews: some View {
        PlaylistsListView()
    }
}



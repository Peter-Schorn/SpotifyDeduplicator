import Foundation
import Logger

/// A namespace of loggers.
enum Loggers {
    
    static let lifeCycle = Logger(label: "lifeCycle", level: .warning)
    
    // MARK: Views
    static let rootView = Logger(label: "RootView", level: .trace)
    static let loginView = Logger(label: "loginView", level: .trace)
    static let playlistsListView = Logger(label: "playlistsListView", level: .trace)
    static let playlistView = Logger(label: "playlistView", level: .notice)
    static let deDuplicateView = Logger(label: "DeDuplicateView", level: .trace)
    static let playlistItemView =  Logger(label: "playlistItemView", level: .trace)
    
    static let cdPlaylist = Logger(label: "cdPlaylist", level: .warning)
    static let cdPlaylistAlbums = Logger(label: "cdPlaylistAlbums", level: .trace)
    static let loadingImages = Logger(label: "loadingImages", level: .warning)
    static let spotifyObservable = Logger(
        label: "spotifyObservable", level: .trace
    )

}

import Foundation
import Logger

/// A namespace of loggers.
enum Loggers {
    
    // MARK: Views
    static let lifeCycle = Logger(label: "lifeCycle", level: .warning)
    static let rootView = Logger(label: "RootView", level: .trace)
    static let loginView = Logger(label: "loginView", level: .trace)
    static let playlistsListView = Logger(label: "playlistsView", level: .trace)
    static let loadingImages = Logger(label: "loadingImages", level: .trace)
    
    static let spotifyObservable = Logger(
        label: "spotifyObservable", level: .trace
    )

}

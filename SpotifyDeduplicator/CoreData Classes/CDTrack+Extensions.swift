import Foundation
import SpotifyWebAPI

extension CDTrack {
    
    /// `"\(self.name) - \(self.artistName)"`.
    var displayName: String {
        guard var displayName = self.name else {
            return "Unknown"
        }
        if let artistName = self.artistName {
            displayName += " - \(artistName)"
        }
        return displayName
    }

    /// Sets `name` and `artistName`.
    func setFromTrack(_ track: Track) {
        self.name = track.name
        self.artistName = track.artists?.first?.name
    }
    
}

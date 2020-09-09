import Foundation
import SpotifyWebAPI


extension PlaylistItem {
    
    
    func isProbablyTheSameAs(_ other: Self) -> Bool {
        
        if self.uri == other.uri { return true }
        
        switch (self, other) {
            case (.track(let track), .track(let otherTrack)):
                // if the name of the tracks and the name of the artists
                // are the same, then the tracks are probably the same
                if track.name == otherTrack.name &&
                        track.artists?.first?.name ==
                        otherTrack.artists?.first?.name {
                    return true
                }
                return false
            case (.episode(let episode), .episode(let otherEpisode)):
                // if the name of the episodes and the names of the
                // shows they appear on are the same, then the episodes
                // are probably the same.
                if episode.name == otherEpisode.name &&
                        episode.show?.name == otherEpisode.show?.name {
                    return true
                }
                return false
            default:
                return false
        }
        
    }
    
}

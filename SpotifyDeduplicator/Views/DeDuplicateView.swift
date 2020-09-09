import SwiftUI
import CoreData
import Combine
import SpotifyWebAPI

struct DeDuplicateView: View {
    
    fileprivate static var debugText: AnyView? = nil
    
    @EnvironmentObject var spotify: Spotify
    
    @FetchRequest(
        entity: CDPlaylist.entity(),
        sortDescriptors: [
            .init(keyPath: \CDPlaylist.index, ascending: true)
        ]
    ) var savedPlaylists: FetchedResults<CDPlaylist>
    
    @State private var deDuplicateCancellables: Set<AnyCancellable> = []
    @State private var deDuplicatingPlaylistsCount = 0

    @State private var noDuplicatesAlertIsPresented = false
    
    @Binding var processingPlaylistsCount: Int?
    
    var body: some View {
        Button(action: deDuplicate) {
            buttonView
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .frame(width: 300, height: 60)
                .background(Color.green)
                .clipShape(Capsule())
                .shadow(radius: 10)
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(
            spotify.isAuthorized &&
                    processingPlaylistsCount == 0 &&
                    deDuplicatingPlaylistsCount == 0
        )
    }
    
    var buttonView: AnyView {
        
        if let text = Self.debugText {
            return text
        }
        
        if let count = processingPlaylistsCount, count > 0 {
            return Text(
                "Processing \(count)/\(savedPlaylists.count) playlists"
            )
            .deDuplicateTextStyle()
            .eraseToAnyView()
            
        }
        else if deDuplicatingPlaylistsCount > 0 {
            let count = deDuplicatingPlaylistsCount
            return Text(
                "De-Depulicating \(count)/\(savedPlaylists.count) playlists"
            )
            .deDuplicateTextStyle()
            .eraseToAnyView()
        }
        else if processingPlaylistsCount == 0 {
            return Text("De-Depulicate")
                .deDuplicateTextStyle()
                .eraseToAnyView()
        }
        return HStack {
            ActivityIndicator(
                isAnimating: .constant(true),
                style: .large
            )
            .scaleEffect(0.8)
            Text("Refreshing Playlists")
                .deDuplicateTextStyle()
        }
        .eraseToAnyView()
        
    }
    
    func deDuplicate() {
        
        Loggers.deDuplicateView.notice("De-Duplicating...")
        self.deDuplicateCancellables.cancellAll()
        deDuplicatingPlaylistsCount = 0

        if savedPlaylists.allSatisfy({ $0.duplicatesCount == 0 }) {
            Loggers.deDuplicateView.trace(
                "No Duplicates in any Playlists"
            )
            spotify.alertTitle =
                    "Congrats! You Have no Duplicates in any of Your Playlists"
            spotify.alertMessage = ""
            spotify.alertIsPresented = true
            return
        }
        
        var playlistsWithDuplicatesCount = 0
        var totalDuplicateTracks = 0
        
        for playlist in savedPlaylists {
            playlist.deDuplicate(spotify)
            if playlist.isDeduplicating {
                playlistsWithDuplicatesCount += 1
                totalDuplicateTracks += playlist.duplicatesCount
                deDuplicatingPlaylistsCount += 1
                Loggers.deDuplicateView.trace(
                    "DeDuplicating \(playlist.name ?? "nil"); " +
                    "count: \(self.deDuplicatingPlaylistsCount as Any)"
                )
                
            }
            
            playlist.finishedDeDuplicating.sink {
                self.deDuplicatingPlaylistsCount -= 1
                Loggers.deDuplicateView.trace(
                    "FINSHED DeDuplicating \(playlist.name ?? "nil"); " +
                    "count: \(self.deDuplicatingPlaylistsCount as Any)"
                )
                if self.deDuplicatingPlaylistsCount <= 0 {
                    self.spotify.alertTitle =
                            "Congrats! You Have no Duplicates in any of Your Playlists"
                    self.spotify.alertMessage = """
                        Removed \(totalDuplicateTracks) Items from \
                        \(playlistsWithDuplicatesCount) Playlists.
                        """
                    self.spotify.alertIsPresented = true
                }
            }
            .store(in: &deDuplicateCancellables)
            
        }
    }
    
}

struct DeDuplicateView_Previews: PreviewProvider {

    static let managedObjectContext =
            (UIApplication.shared.delegate as! AppDelegate)
            .persistentContainer.viewContext
    
    static let spotify: Spotify = {
        
        DeDuplicateView.debugText = text
        
        let spotify = Spotify()
        spotify.isAuthorized = true
        return spotify
    }()
    
    static var count: Int? = 5

    static let text = Text(
        // "De-Duplicate"
        "Processing 999999/100000000 Playlistsss"
    )
    .font(.title)
    .fontWeight(.light)
    .lineLimit(1)
    .minimumScaleFactor(0.5)
    .eraseToAnyView()
    
    static var previews: some View {
        ZStack {
            List(0...20, id: \.self) { i in
                Text("\(i)")
                    .frame(height: 70)
            }
            .padding(.bottom, 50)
            VStack {
                Spacer()
                DeDuplicateView(
                    processingPlaylistsCount: .constant(count)
                )
                .padding(.bottom, 15)
                .environmentObject(spotify)
                .environment(\.managedObjectContext, managedObjectContext)
            }
        }
        .previewDevice(.init(rawValue: "iPhone 7"))
    }
}

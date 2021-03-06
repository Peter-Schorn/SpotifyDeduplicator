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

    @State private var totalPlaylistsWithDuplicates = 0
    
    @State private var deDuplicateCancellables: Set<AnyCancellable> = []
    @State private var deDuplicatingPlaylistsCount = 0 {
        didSet {
            print("deDuplicatingPlaylistsCount: \(deDuplicatingPlaylistsCount)")
        }
    }

    @Binding var processingPlaylistsCount: Int {
        didSet {
            print("processingPlaylistsCount: \(processingPlaylistsCount)")
        }
    }
    
    var body: some View {
        Button(action: deDuplicate) {
            buttonView
                .deDuplicateButtonStyle()
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(
            spotify.isAuthorized &&
                    processingPlaylistsCount <= 0 &&
                    deDuplicatingPlaylistsCount <= 0
        )
    }
    
    var buttonView: AnyView {
        
        if let text = Self.debugText {
            return text
        }
        
        if processingPlaylistsCount > 0 {
            let count = processingPlaylistsCount
            return Text(
                "Processing \(count)/\(savedPlaylists.count) Playlists"
            )
            .deDuplicateTextStyle()
            .eraseToAnyView()
            
        }
        else if deDuplicatingPlaylistsCount > 0 {
            let count = deDuplicatingPlaylistsCount
            return Text(
                "De-Depulicating \(count)/\(totalPlaylistsWithDuplicates) Playlists"
            )
            .deDuplicateTextStyle()
            .eraseToAnyView()
        }
        else if spotify.isLoadingPlaylists {
            return HStack {
                ActivityIndicator(
                    isAnimating: .constant(true),
                    style: .large
                )
                .scaleEffect(0.8)
                Text("Reloading Playlists")
                    .deDuplicateTextStyle()
            }
            .eraseToAnyView()
        }
        else {
            return Text("De-Depulicate")
                .deDuplicateTextStyle()
                .eraseToAnyView()
        }
        
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
                    "You Have no Duplicates in any of Your Playlists"
            spotify.alertMessage = ""
            spotify.alertIsPresented = true
            return
        }
        
        totalPlaylistsWithDuplicates = 0
        for playlist in savedPlaylists {
            if !playlist.duplicatePlaylistItems.isEmpty {
                totalPlaylistsWithDuplicates += 1
            }
        }
        
        var totalDuplicateItems = 0
        
        for playlist in savedPlaylists {
            playlist.deDuplicate(spotify)?
                .sink(receiveCompletion: { completion in
                    self.deDuplicatingPlaylistsCount -= 1
                    Loggers.deDuplicateView.trace(
                        "FINSHED DeDuplicating \(playlist.name ?? "nil"); " +
                        "count: \(self.deDuplicatingPlaylistsCount as Any)"
                    )
                    if self.deDuplicatingPlaylistsCount <= 0 {
                        switch completion {
                            case .finished:
                                self.spotify.alertTitle = """
                                    Congrats! All Duplicates Have Been Removed from Your Playlists
                                    """
                                self.spotify.alertMessage = """
                                    Removed \(totalDuplicateItems) Items from \
                                    \(self.totalPlaylistsWithDuplicates) Playlists.
                                    """
                                self.spotify.alertIsPresented = true
                            case .failure(let error):
                                self.spotify.alertTitle = """
                                    Duplicates Could Not Be Removed From One Or More Playlists
                                    """
                                self.spotify.alertMessage = error.localizedDescription
                                self.spotify.alertIsPresented = true
                        }
                    }
                })
                .store(in: &deDuplicateCancellables)
            
            if playlist.isDeduplicating {
                totalDuplicateItems += Int(playlist.duplicatesCount)
                deDuplicatingPlaylistsCount += 1
                Loggers.deDuplicateView.trace(
                    "DeDuplicating \(playlist.name ?? "nil"); " +
                    "count: \(self.deDuplicatingPlaylistsCount as Any)"
                )
                
            }
            
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
    
    static var count = 5

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

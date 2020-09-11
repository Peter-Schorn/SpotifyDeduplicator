import SwiftUI
import Combine
import SpotifyWebAPI
import CoreData

struct RootView: View {
    
    @EnvironmentObject var spotify: Spotify

    @State private var cancellables: Set<AnyCancellable> = []
    
    @State private var didAuthorizecancellable: AnyCancellable? = nil
    
    @State private var loginAlertIsPresented = false
    @State private var loginErrorMessage = ""
    
    var body: some View {
        
        NavigationView {
            
            PlaylistsListView()
            .padding(.top)
            .navigationBarTitle(
                "Spotify Deduplicator",
                displayMode: .inline
            )
            .navigationBarItems(
                leading: HStack {
                    refreshButton
                    filterButton
                },
                trailing: logoutButton
            )
            
        }
        .modifier(LoginView())
        .onAppear(perform: subscribeToDidAuthorizeSubject)
        .alert(
            isPresented: $loginAlertIsPresented,
            content: makeLoginAlert
        )
    }
    
    func makeLoginAlert() -> Alert {
        Alert(
            title: Text(
                "Couldn't authenticate with your account"
            ),
            message: Text(loginErrorMessage)
        )
    }

    var refreshButton: some View {
        Button(action: spotify.didPressRefreshSubject.send) {
            Image(systemName: "arrow.clockwise")
                .font(.title)
                .scaleEffect(0.9)
        }
        .disabled(!spotify.isAuthorized || spotify.isLoadingPlaylists)
    }
    
    var filterButton: some View {
        Image(
            systemName: spotify.isSortingByIndex ?
                    "line.horizontal.3.decrease.circle" :
                    "line.horizontal.3.decrease.circle.fill"
        )
        .font(.title)
        .foregroundColor(.blue)
        .padding(.horizontal)
        .offset(y: 2)
        .scaleEffect(0.9)
        .onTapGesture {
            self.spotify.isSortingByIndex.toggle()
        }
        .disabled(!spotify.isAuthorized)
    }
    
    var logoutButton: some View {
        Button(action: logout) {
            Text("Logout")
                .foregroundColor(.white)
                .padding(7)
                .background(Color(#colorLiteral(red: 0.3923448698, green: 0.7200681584, blue: 0.19703095, alpha: 1)))
                .cornerRadius(10)
                .shadow(radius: 2)
            
        }
    }

    func logout() {
        Loggers.rootView.debug("logout")
        spotify.api.authorizationManager.deauthorize()
    }
    
    func subscribeToDidAuthorizeSubject() {
        self.didAuthorizecancellable = spotify.didAuthorizeSubject
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    Loggers.loginView.error(
                        "couldn't authorize app:\n\(error)"
                    )
                    if let authError = error as? SpotifyAuthorizationError,
                            authError.accessWasDenied {
                        self.loginErrorMessage =
                                "You denied the authorization request :("
                    }
                    else {
                        self.loginErrorMessage = error.localizedDescription
                    }
                    self.loginAlertIsPresented = true
                    
                }
                else {
                    Loggers.loginView.trace("successfully authorized")
                }
            })
    }
    
}

struct RootView_Previews: PreviewProvider {

    static let spotify = Spotify()
    
    static var previews: some View {
        RootView()
            .environmentObject(spotify)
            .onAppear(perform: onAppear)
    }
    
    static func onAppear() {
        spotify.isAuthorized = true
    
    }
}

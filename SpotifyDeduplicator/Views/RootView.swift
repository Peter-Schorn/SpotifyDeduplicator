import SwiftUI
import Combine
import SpotifyWebAPI

struct RootView: View {
    var body: some View {
        Text("Hello, World!")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}


struct RootView: View {
    
    @EnvironmentObject var spotify: Spotify

    // @ObservedObject var playlistModel = PlaylistModel()

    @State private var cancellables: Set<AnyCancellable> = []
    
    @State private var didAuthorizecancellable: AnyCancellable? = nil
    
    @State private var loginErrorIsPresented = false
    @State private var loginErrorMessage = ""
    
    var body: some View {
        
        NavigationView {
            Text("Temp")
        }
        .modifier(LoginView())
        .onAppear(perform:  subscribeToDidAuthorizeSubject)
        .alert(isPresented: $loginErrorIsPresented) {
            Alert(
                title: Text("Couldn't authenticate with your account"),
                message: Text(loginErrorMessage)
            )
        }
    }
    
    var logoutButton: some View {
        Button(action: logout) {
            Text("Logout")
                .foregroundColor(.white)
                .padding(7)
                .background(Color(#colorLiteral(red: 0.3923448698, green: 0.7200681584, blue: 0.19703095, alpha: 1)))
                .cornerRadius(10)
                .shadow(radius: 5)
            
        }
    }

    func logout() {
        withAnimation(LoginView.animation) {
            Loggers.rootView.debug("logout")
            spotify.api.authorizationManager.deauthorize()
        }
    }
    
    func subscribeToDidAuthorizeSubject() {
        
        self.didAuthorizecancellable = spotify.didAuthorizeSubject
            .sink { completion in
                
                if case .failure(let error) = completion {
                    Loggers.loginView.error(
                        "couldn't authorize app:\n\(error)"
                    )
                    if let authError = error as? SpotifyAuthorizationError {
                        if authError.accessWasDenied {
                            self.loginErrorMessage =
                            "You denied the authorization request"
                        }
                    }
                    else {
                        self.loginErrorMessage = error.localizedDescription
                    }
                    self.loginErrorIsPresented = true
                    
                }
            }
    }
    
}

// struct ContentView_Previews: PreviewProvider {
//
//     static var previews: some View {
//         RootView()
//             .environmentObject(Spotify())
//     }
// }

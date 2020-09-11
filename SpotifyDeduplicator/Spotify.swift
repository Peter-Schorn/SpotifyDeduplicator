import Foundation
import Combine
import SwiftUI
import Logger
import KeychainAccess
import CoreData
import SpotifyWebAPI

final class Spotify: ObservableObject {
    
    private static let clientID: String = {
        if let clientID = ProcessInfo.processInfo
                .environment["client_id"] {
            return clientID
        }
        fatalError("Could not find 'client_id' in environment variables")
    }()
    
    private static let clientSecret: String = {
        if let clientSecret = ProcessInfo.processInfo
                .environment["client_secret"] {
            return clientSecret
        }
        fatalError("Could not find 'client_secret' in environment variables")
    }()
    
    static let authRedirectURL = URL(
        string: "peter-schorn-spotify-deduplicator://login-callback"
    )!
    
    // MARK: - Published Properties -
    
    @Published var isAuthorized = false
    @Published var isRetrievingTokens = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var alertIsPresented = false
    @Published var isSortingByIndex = true
    @Published var isLoadingPlaylists = false
    
    // MARK: - Subjects -
    
    /// Emits after the request for access and refresh tokens
    /// completes.
    let didAuthorizeSubject = PassthroughSubject<Void, Error>()

    let didPressRefreshSubject = PassthroughSubject<Void, Never>()

    
    var cancellables: [AnyCancellable] = []

    let keychain = Keychain(
        service: "Peter-Schorn.SpotifyDeduplicator"
    )
    
    let api: SpotifyAPI<AuthorizationCodeFlowManager> = {
        let api = SpotifyAPI(
            authorizationManager: AuthorizationCodeFlowManager(
                clientId: Spotify.clientID,
                clientSecret: Spotify.clientSecret
            )
        )
        // api.apiRequestLogger.level = .trace
        Loggers.spotifyObservable.trace("created SpotifyAPI")
        SpotifyDecodingError.dataDumpfolder = URL(
            fileURLWithPath: "/Users/pschorn/Desktop/"
        )
        return api
    }()
    
    // MARK: - Methods -
    
    /// Called in application(_:didFinishLaunchingWithOptions:)
    func setup() {
        
        // check to see if `authorizationManager` is already stored in
        // the keychain. if so, assign it to `api.authorizationManager`.
        do {
           
            if let authData = keychain[data: KeychainKeys.authorizationManager] {
                Loggers.spotifyObservable.trace(
                    "found authorizationManager in keychain"
                )
                let authorizationManager = try JSONDecoder().decode(
                    AuthorizationCodeFlowManager.self, from: authData
                )
                api.authorizationManager = authorizationManager
                handleChangesToAuthorizationManager()
            }
            else {
                Loggers.spotifyObservable.trace(
                    "didn't find authorizationManager in keychain"
                )
            }
            
        } catch {
            Loggers.spotifyObservable.error(
                "couldn't decode authorizationManager " +
                "from keychain:\n\(error)"
            )
        }
        
        // subscribe to `authorizationManagerDidChange` so that the keychain
        // can be updated every time `authorizationManager` changes.
        self.api.authorizationManagerDidChange
            .receive(on: RunLoop.main)
            .sink(receiveValue: handleChangesToAuthorizationManager)
            .store(in: &cancellables)
    
    }
        
    func authorize() {
        let url = api.authorizationManager.makeAuthorizationURL(
            redirectURI: Self.authRedirectURL,
            showDialog: true,
            scopes: [
                .playlistReadPrivate,
                .playlistModifyPublic,
                .playlistModifyPrivate,
                .playlistReadCollaborative
            ]
        )!
        UIApplication.shared.open(url)
    }
    
    /// Updates the state of `LoginView` and saves changes to
    /// `authorizationManager` to the keychain.
    func handleChangesToAuthorizationManager() {
        
        Loggers.spotifyObservable.trace(
            "handleChangesToAuthorizationManager"
        )
        
        withAnimation(LoginView.animation) {
            self.isAuthorized = self.api.authorizationManager.isAuthorized()
        }
        
        do {
            guard self.api.authorizationManager.accessToken != nil else {
                // The user pressed the logout button in the navigation bar.
                Loggers.spotifyObservable.trace(
                    "removing authorizationManager and userId from keychain"
                )
                try keychain.remove(KeychainKeys.authorizationManager)
                try keychain.remove(KeychainKeys.userId)
                return
            }
            let authData = try JSONEncoder().encode(api.authorizationManager)
            keychain[data: KeychainKeys.authorizationManager] = authData
            
        } catch {
            Loggers.spotifyObservable.error(
                "couldn't encode authorizationManager for storage " +
                "or remove from keychain:\n\(error)"
            )
        }
        
    }
    
    func getCurrentUserId() -> AnyPublisher<String, Error> {
        // if the user id already exists in the keychain,
        // then use it
        if let id = self.keychain[string: KeychainKeys.userId] {
            return Result<String, Error>.Publisher(.success(id))
                .eraseToAnyPublisher()
        }
        // else, retrieve the user id from the web API
        // and save it back to the keychain.
        return self.api.currentUserProfile()
            .map { profile -> String in
                let id = profile.id
                self.keychain[string: KeychainKeys.userId] = id
                return id
            }
            .eraseToAnyPublisher()
    }
    
}


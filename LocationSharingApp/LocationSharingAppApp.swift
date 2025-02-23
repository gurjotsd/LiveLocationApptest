import SwiftUI
import Firebase
import FirebaseAuth

@main
struct LocationSharingApp: App {
    @StateObject var session = SessionStore()
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            if session.currentUser != nil {
                HomeView()
                    .environmentObject(session)
            } else {
                LoginView()
                    .environmentObject(session)
            }
        }
    }
}


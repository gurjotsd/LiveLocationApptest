import SwiftUI
import Firebase
import FirebaseAuth

@main
struct LocationSharingApp: App {
    @StateObject var session = SessionStore()
    
    init() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Optional: Enable Firebase debug mode for development
        #if DEBUG
        // Uncomment this line if you want to see detailed Firebase logs
        // FirebaseConfiguration.shared.setLoggerLevel(.debug)
        #endif
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


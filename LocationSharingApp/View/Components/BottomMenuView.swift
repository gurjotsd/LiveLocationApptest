import SwiftUI
import FirebaseAuth

struct BottomMenuView: View {
    @Binding var showMenu: Bool
    @State private var selectedDestination: NavigationDestination?
    
    enum NavigationDestination: Hashable {
        case friends
        case requests
        case profile
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Menu Content
            HStack {
                // Friends Button
                MenuIconButton(
                    icon: "person.2.fill",
                    title: "Friends",
                    action: { selectedDestination = .friends }
                )
                .frame(maxWidth: .infinity)
                
                // Requests Button
                MenuIconButton(
                    icon: "person.badge.plus",
                    title: "Requests",
                    action: { selectedDestination = .requests }
                )
                .frame(maxWidth: .infinity)
                
                // Profile Button
                MenuIconButton(
                    icon: "person.circle",
                    title: "Profile",
                    action: { selectedDestination = .profile }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial.opacity(0.9))
        .ignoresSafeArea(edges: .bottom)
        .navigationDestination(isPresented: Binding(
            get: { selectedDestination != nil },
            set: { if !$0 { selectedDestination = nil } }
        )) {
            if let destination = selectedDestination {
                switch destination {
                case .friends:
                    FriendsListView()
                case .requests:
                    RequestsView()
                case .profile:
                    if let email = Auth.auth().currentUser?.email {
                        ProfileView(userEmail: email, isCurrentUser: true)
                    }
                }
            }
        }
    }
}

struct MenuIconButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    BottomMenuView(showMenu: .constant(true))
} 

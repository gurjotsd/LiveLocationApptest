import SwiftUI
import MapKit
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var locationManager = LocationManager()
    @State private var friends: [Friend] = []
    @State private var selectedFriend: Friend?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    
    struct Friend: Identifiable {
        let id: String
        let email: String
        let displayName: String
        var location: CLLocationCoordinate2D?
        var lastSeen: Date?
        
        var isOnline: Bool {
            guard let lastSeen = lastSeen else { return false }
            return Date().timeIntervalSince(lastSeen) < 300 // 5 minutes
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map View
                if let region = locationManager.region {
                    Map(initialPosition: .region(region)) {
                        UserAnnotation()
                        
                        ForEach(friends) { friend in
                            if let location = friend.location {
                                Marker(friend.displayName, coordinate: location)
                                    .tint(friend.isOnline ? .green : .gray)
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .mapControls {
                        MapCompass()
                        MapUserLocationButton()
                    }
                    
                } else {
                    ProgressView()
                }
                
                // Bottom Menu Bar
                HStack {
                    NavigationLink(destination: FriendsListView()) {
                        VStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 24))
                            Text("Friends")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                    
                    NavigationLink(destination: RequestsView()) {
                        VStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 24))
                            Text("Add/Requests")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                    
                    NavigationLink(destination: ProfileView(userEmail: Auth.auth().currentUser?.email ?? "", isCurrentUser: true)) {
                        VStack(spacing: 6) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 24))
                            Text("Profile")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .background(.black.opacity(0.8))
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarHidden(true)
            .onAppear {
                locationManager.requestLocationPermission()
                startFriendsLocationListener()
            }
        }
    }
    
    private func startFriendsLocationListener() {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        let db = Firestore.firestore()
        
        // First, get the user's friends list
        db.collection("users").document(currentUserEmail).addSnapshotListener { snapshot, error in
            guard let data = snapshot?.data(),
                  let friendsList = data["friends"] as? [String] else { return }
            
            // Then listen for location updates from all friends
            for friendEmail in friendsList {
                db.collection("users").document(friendEmail)
                    .addSnapshotListener { friendSnapshot, friendError in
                        guard let friendData = friendSnapshot?.data() else { return }
                        
                        let latitude = friendData["latitude"] as? Double
                        let longitude = friendData["longitude"] as? Double
                        let displayName = friendData["displayName"] as? String ?? "Unknown"
                        let lastSeen = (friendData["lastSeen"] as? Timestamp)?.dateValue()
                        
                        var location: CLLocationCoordinate2D?
                        if let lat = latitude, let lon = longitude {
                            location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        }
                        
                        // Update or add friend to the list
                        DispatchQueue.main.async {
                            if let index = friends.firstIndex(where: { $0.email == friendEmail }) {
                                friends[index].location = location
                                friends[index].lastSeen = lastSeen
                            } else {
                                let friend = Friend(
                                    id: friendEmail,
                                    email: friendEmail,
                                    displayName: displayName,
                                    location: location,
                                    lastSeen: lastSeen
                                )
                                friends.append(friend)
                            }
                        }
                    }
            }
        }
    }
}

#Preview {
    HomeView()
}


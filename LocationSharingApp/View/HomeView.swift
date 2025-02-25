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
    @State private var friendsListener: ListenerRegistration?
    @State private var locationListener: ListenerRegistration?
    
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
                
                // Bottom Menu Bar needs workinh on
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
                startLocationListener()
            }
            .onDisappear {
                locationListener?.remove()
                friendsListener?.remove()
            }
        }
    }
    
    private func startLocationListener() {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        let db = Firestore.firestore()
        
        // First, listen for changes to the current user's friends list
        let userRef = db.collection("users").document(currentUserEmail)
        friendsListener = userRef.addSnapshotListener { snapshot, error in
            guard let data = snapshot?.data(),
                  let friendsList = data["friends"] as? [String] else { return }
            
            // Remove pins for users who are no longer friends
            DispatchQueue.main.async {
                self.friends = self.friends.filter { friend in
                    friendsList.contains(friend.email)
                }
            }
        }
        
        // Then listen for location updates from current friends
        locationListener = db.collection("users")
            .whereField("friends", arrayContains: currentUserEmail)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error listening for location updates: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    for document in documents {
                        let data = document.data()
                        guard let latitude = data["latitude"] as? Double,
                              let longitude = data["longitude"] as? Double,
                              let displayName = data["displayName"] as? String,
                              let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue() else {
                            continue
                        }
                        
                        let email = document.documentID
                        let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                        
                        // Update or add friend location
                        if let index = self.friends.firstIndex(where: { $0.email == email }) {
                            self.friends[index].location = location
                            self.friends[index].lastSeen = lastSeen
                        } else {
                            let friend = Friend(
                                id: email,
                                email: email,
                                displayName: displayName,
                                location: location,
                                lastSeen: lastSeen
                            )
                            self.friends.append(friend)
                        }
                    }
                }
            }
    }
}

#Preview {
    HomeView()
}


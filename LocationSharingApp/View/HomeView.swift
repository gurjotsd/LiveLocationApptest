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
    @State private var selectedTab = 0
    @State private var showingFriendsList = false
    @State private var showingRequests = false
    @State private var showingProfile = false
    
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
    
    var bottomMenu: some View {
        HStack(spacing: 16) {
            TabBarButton(
                title: "Friends",
                icon: "person.2.fill",
                isActive: selectedTab == 0
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 0
                    showingFriendsList = true
                }
            }
            
            TabBarButton(
                title: "Add",
                icon: "person.badge.plus",
                isActive: selectedTab == 1
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 1
                    showingRequests = true
                }
            }
            
            TabBarButton(
                title: "Profile",
                icon: "person.circle.fill",
                isActive: selectedTab == 2
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 2
                    showingProfile = true
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .padding(.horizontal)
        .padding(.bottom, 20)
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
                
                bottomMenu
            }
            .navigationDestination(isPresented: $showingFriendsList) {
                FriendsListView()
            }
            .navigationDestination(isPresented: $showingRequests) {
                RequestsView()
            }
            .navigationDestination(isPresented: $showingProfile) {
                ProfileView(userEmail: Auth.auth().currentUser?.email ?? "", isCurrentUser: true)
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
                        let email = document.documentID
                        let displayName = data["displayName"] as? String ?? ""
                        let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue()
                        let latitude = data["latitude"] as? Double
                        let longitude = data["longitude"] as? Double
                        
                        let location = (latitude.flatMap { lat in
                            longitude.flatMap { lon in
                                CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            }
                        })
                        
                        // Update or add friend
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

// First, let's create a better TabBarButton
struct TabBarButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? .blue : .gray)
                .frame(height: 24)
                .scaleEffect(isActive ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isActive)
            
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? .blue : .gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.blue.opacity(0.1) : .clear)
                .animation(.spring(response: 0.3), value: isActive)
        )
    }
}

struct CustomMapAnnotation: View {
    let friend: Friend
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(friend.isOnline ? .green : .gray)
                .background(
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 4)
                )
            
            Text(friend.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white)
                .cornerRadius(8)
                .shadow(radius: 2)
        }
    }
}

struct LocationStatusBar: View {
    @ObservedObject var locationManager: LocationManager
    
    var body: some View {
        HStack {
            Image(systemName: locationManager.isAuthorized ? "location.fill" : "location.slash.fill")
                .foregroundColor(locationManager.isAuthorized ? .green : .red)
            
            Text(locationManager.isAuthorized ? "Sharing Location" : "Location Disabled")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .padding(.top)
    }
}

#Preview {
    HomeView()
}


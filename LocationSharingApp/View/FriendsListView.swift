import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import MapKit
import FirebaseStorage

// Move Friend struct outside of FriendsListView to make it accessible to FriendRow
struct Friend: Identifiable, Sendable {
    let id: String
    let email: String
    let displayName: String
    var location: CLLocationCoordinate2D?
    var lastSeen: Date?
    var profileImageUrl: String?
    
    var isOnline: Bool {
        guard let lastSeen = lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < 3000000 // 5 minutes
    }
    
    // Add initializer to ensure id is always set to email
    init(email: String, displayName: String, location: CLLocationCoordinate2D? = nil, 
         lastSeen: Date? = nil, profileImageUrl: String? = nil) {
        self.id = email
        self.email = email
        self.displayName = displayName
        self.location = location
        self.lastSeen = lastSeen
        self.profileImageUrl = profileImageUrl
    }
}

struct FriendsListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var showingProfile = false
    @State private var selectedFriend: Friend?
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    ))
    
    // Add this property to store the listener
    @State private var locationListener: ListenerRegistration?
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                Text("Friends")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            
            // Larger Map
            Map(position: $cameraPosition) {
                ForEach(friends) { friend in
                    if let location = friend.location {
                        Annotation(friend.displayName, coordinate: location) {
                            VStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(friend.isOnline ? .green : .gray)
                                    .background(Circle().fill(.white))
                            }
                        }
                    }
                }
            }
            .frame(height: UIScreen.main.bounds.height * 0.4) // 40% of screen height
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
            .shadow(radius: 5)
            
            // Friends list
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if friends.isEmpty {
                EmptyFriendsView()
            } else {
                List {
                    ForEach(friends) { friend in
                        FriendRow(friend: friend) {
                            selectedFriend = friend
                            showingProfile = true
                        } locationTapAction: {
                            selectedFriend = friend
                            updateMapRegion(for: friend)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await removeFriend(friend)
                                }
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await fetchFriends()
                startLocationListener()
            }
        }
        .onDisappear {
            locationListener?.remove()
        }
        .sheet(isPresented: $showingProfile) {
            if let friend = selectedFriend {
                ProfileView(userEmail: friend.email, isCurrentUser: false)
            }
        }
    }
    
    private func updateMapRegion(for friend: Friend) {
        guard let location = friend.location else {
            print("⚠️ No location available for friend: \(friend.displayName)")
            return
        }
        
        print("🗺️ Updating map region for: \(friend.displayName)")
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
    }
    
    private func fetchFriends() async {
        print("📥 Starting friends fetch...")
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else {
            print("❌ No authenticated user")
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            let snapshot = try await db.collection("users").document(currentUserEmail).getDocument()
            guard let data = snapshot.data(),
                  let friendsList = data["friends"] as? [String] else {
                print("❌ No friends list found")
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            print("📋 Found \(friendsList.count) friends")
            var tempFriends: [Friend] = []
            
            for friendEmail in friendsList {
                if let friend = try await fetchFriendData(email: friendEmail) {
                    tempFriends.append(friend)
                }
            }
            
            await MainActor.run {
                withAnimation {
                    friends = tempFriends.sorted { $0.displayName < $1.displayName }
                    if let firstLocation = friends.first?.location {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: firstLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        ))
                    }
                }
                isLoading = false
            }
            print("✅ Friends list updated successfully")
        } catch {
            print("❌ Error fetching friends: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func fetchFriendData(email: String) async throws -> Friend? {
        print("📥 Fetching data for friend: \(email)")
        let snapshot = try await db.collection("users").document(email).getDocument()
        
        guard let data = snapshot.data(),
              let displayName = data["displayName"] as? String else {
            print("❌ Invalid friend data for: \(email)")
            return nil
        }
        
        let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue()
        let latitude = data["latitude"] as? Double
        let longitude = data["longitude"] as? Double
        let profileImageUrl = data["profileImageUrl"] as? String
        
        var location: CLLocationCoordinate2D?
        if let lat = latitude, let lon = longitude {
            location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        print("✅ Successfully fetched friend data: \(displayName)")
        
        return Friend(
            email: email,
            displayName: displayName,
            location: location,
            lastSeen: lastSeen,
            profileImageUrl: profileImageUrl
        )
    }
    
    private func startLocationListener() {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else {
            print("❌ Cannot start location listener - no authenticated user")
            return
        }
        
        // Cancel existing listener if any
        locationListener?.remove()
        
        print("🎯 Starting location listener")
        let query = db.collection("users").whereField("friends", arrayContains: currentUserEmail)
        
        locationListener = query.addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Firebase connection error: \(error.localizedDescription)")
                // Attempt to reconnect after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.startLocationListener()
                }
                return
            }
            
            guard let documents = snapshot?.documents else { return }
            
            for document in documents {
                let data = document.data()
                guard let latitude = data["latitude"] as? Double,
                      let longitude = data["longitude"] as? Double,
                      let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue() else {
                    continue
                }
                
                DispatchQueue.main.async {
                    if let index = self.friends.firstIndex(where: { $0.email == document.documentID }) {
                        let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                        withAnimation {
                            self.friends[index].location = location
                            self.friends[index].lastSeen = lastSeen
                            
                            // If this is the currently selected friend, update the map
                            if let selectedFriend = self.selectedFriend,
                               selectedFriend.email == document.documentID {
                                self.cameraPosition = .region(MKCoordinateRegion(
                                    center: location,
                                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                ))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Helper function to format location
    private func formatLocation(_ coordinate: CLLocationCoordinate2D) -> String {
        // You can integrate with reverse geocoding here
        return "Lat: \(String(format: "%.2f", coordinate.latitude)), Long: \(String(format: "%.2f", coordinate.longitude))"
    }
    
    // Helper function to format last seen time
    private func formatLastSeen(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func removeFriend(_ friend: Friend) async {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        let friendEmail = friend.email // Capture the email value
        let friendName = friend.displayName // Capture the name value
        
        print("🗑️ Attempting to remove friend: \(friendName)")
        
        do {
            let batch = db.batch()
            
            // Remove from current user's friends list
            let currentUserRef = db.collection("users").document(currentUserEmail)
            batch.updateData([
                "friends": FieldValue.arrayRemove([friendEmail])
            ], forDocument: currentUserRef)
            
            // Remove current user from friend's friends list
            let friendRef = db.collection("users").document(friendEmail)
            batch.updateData([
                "friends": FieldValue.arrayRemove([currentUserEmail])
            ], forDocument: friendRef)
            
            try await batch.commit()
            
            await MainActor.run {
                withAnimation {
                    friends.removeAll { $0.id == friendEmail }
                    if let firstLocation = friends.first?.location {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: firstLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        ))
                    }
                }
                print("✅ Successfully removed friend: \(friendName)")
            }
        } catch {
            print("❌ Failed to remove friend: \(error.localizedDescription)")
        }
    }
}

// Custom shape for location marker
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct FriendRow: View {
    let friend: Friend
    let profileTapAction: () -> Void
    let locationTapAction: () -> Void
    @State private var locationName: String = "Loading location..."
    @State private var profileImage: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image button as a separate tappable area
            ProfileImageButton(
                image: profileImage,
                displayName: friend.displayName,
                action: profileTapAction
            )
            
            // Location info area as a separate button
            Button(action: locationTapAction) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(friend.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(locationName)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(friend.isOnline ? .green : .gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
        .onAppear {
            loadProfileImage()
            if let location = friend.location {
                updateLocationName(for: location)
            } else {
                locationName = "Location unavailable"
            }
        }
    }
    
    private func loadProfileImage() {
        guard let imageUrl = friend.profileImageUrl,
              let url = URL(string: imageUrl) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.profileImage = image
                }
            }
        }.resume()
    }
    
    private func updateLocationName(for coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    let city = placemark.locality ?? ""
                    let country = placemark.country ?? ""
                    locationName = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
                } else {
                    locationName = "Location unavailable"
                }
            }
        }
    }
}

// Custom button for profile image
struct ProfileImageButton: View {
    let image: UIImage?
    let displayName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(displayName.prefix(1).uppercased())
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                    )
            }
        }
    }
}

// Custom button style for location area
struct LocationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
    }
}

struct EmptyFriendsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            Text("No Friends Yet")
                .font(.title2)
                .fontWeight(.medium)
            Text("Add friends to share locations with them")
                .foregroundColor(.gray)
        }
        .frame(maxHeight: .infinity)
    }
}

struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        FriendsListView()
    }
}

// Add this new view for location text
struct LocationText: View {
    let coordinate: CLLocationCoordinate2D
    @State private var locationName: String = "Loading location..."
    
    var body: some View {
        Text(locationName)
            .font(.caption)
            .onAppear {
                fetchLocationName()
            }
    }
    
    private func fetchLocationName() {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    let city = placemark.locality ?? ""
                    let country = placemark.country ?? ""
                    locationName = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
                } else {
                    locationName = "Location unavailable"
                }
            }
        }
    }
}



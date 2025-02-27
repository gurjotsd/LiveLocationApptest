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
    var lastKnownLocation: CLLocationCoordinate2D?
    var profileImageUrl: String?
    
    var isOnline: Bool {
        guard let lastSeen = lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < 300 // 5 minutes threshold
    }
    
    // Add initializer to ensure id is always set to email
    init(email: String, displayName: String, location: CLLocationCoordinate2D? = nil,
         lastSeen: Date? = nil, lastKnownLocation: CLLocationCoordinate2D? = nil,
         profileImageUrl: String? = nil) {
        self.id = email
        self.email = email
        self.displayName = displayName
        self.location = location
        self.lastSeen = lastSeen
        self.lastKnownLocation = location ?? lastKnownLocation
        self.profileImageUrl = profileImageUrl
    }
    
    // Helper to get the best available location
    var bestAvailableLocation: CLLocationCoordinate2D? {
        return location ?? lastKnownLocation
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
    
    @State private var locationListener: ListenerRegistration?
    private let db = Firestore.firestore()
    @State private var searchText = ""
    @State private var selectedFilter: FriendFilter = .all
    
    enum FriendFilter {
        case all
        case online
        case offline
    }
    
    var filteredFriends: [Friend] {
        let filtered = friends.filter { friend in
            if searchText.isEmpty {
                return true
            }
            return friend.displayName.lowercased().contains(searchText.lowercased()) ||
                   friend.email.lowercased().contains(searchText.lowercased())
        }
        
        switch selectedFilter {
        case .all:
            return filtered
        case .online:
            return filtered.filter { $0.isOnline }
        case .offline:
            return filtered.filter { !$0.isOnline }
        }
    }
    
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
            
            // Search and Filter Bar
            HStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search friends", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(8)
                .background(Color.cardBackground)
                .cornerRadius(8)
                
                // Filter Menu
                Menu {
                    Button(action: { selectedFilter = .all }) {
                        Label("All", systemImage: "person.3")
                    }
                    Button(action: { selectedFilter = .online }) {
                        Label("Online", systemImage: "circle.fill")
                            .foregroundColor(.green)
                    }
                    Button(action: { selectedFilter = .offline }) {
                        Label("Offline", systemImage: "circle.fill")
                            .foregroundColor(.gray)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            
            // Map View (Collapsible)
            DisclosureGroup("Map View") {
                Map(position: $cameraPosition) {
                    ForEach(filteredFriends) { friend in
                        if let location = friend.bestAvailableLocation {
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
                .frame(height: UIScreen.main.bounds.height * 0.3)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding()
            
            // Friends List with sections
            List {
                if !filteredFriends.filter({ $0.isOnline }).isEmpty {
                    Section("Online") {
                        ForEach(filteredFriends.filter { $0.isOnline }) { friend in
                            FriendRow(friend: friend) {
                                selectedFriend = friend
                                showingProfile = true
                            } locationTapAction: {
                                if let location = friend.bestAvailableLocation {
                                    withAnimation {
                                        cameraPosition = .region(MKCoordinateRegion(
                                            center: location,
                                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                        ))
                                    }
                                }
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
                }
                
                if !filteredFriends.filter({ !$0.isOnline }).isEmpty {
                    Section("Offline") {
                        ForEach(filteredFriends.filter { !$0.isOnline }) { friend in
                            FriendRow(friend: friend) {
                                selectedFriend = friend
                                showingProfile = true
                            } locationTapAction: {
                                if let location = friend.bestAvailableLocation {
                                    withAnimation {
                                        cameraPosition = .region(MKCoordinateRegion(
                                            center: location,
                                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                        ))
                                    }
                                }
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
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingProfile) {
            if let friend = selectedFriend {
                ProfileView(userEmail: friend.email, isCurrentUser: false)
            }
        }
        .onAppear {
            startFriendsListener()
        }
        .onDisappear {
            locationListener?.remove()
        }
    }
    
    // Add this function to update the map region to show all friends
    private func updateMapRegion() {
        guard !friends.isEmpty else { return }
        
        var coordinates: [CLLocationCoordinate2D] = []
        
        // Collect all available locations
        for friend in friends {
            if let location = friend.bestAvailableLocation {
                coordinates.append(location)
            }
        }
        
        guard !coordinates.isEmpty else { return }
        
        // Calculate the center point
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        
        let center = CLLocationCoordinate2D(
            latitude: (latitudes.max()! + latitudes.min()!) / 2,
            longitude: (longitudes.max()! + longitudes.min()!) / 2
        )
        
        // Calculate the span to show all points
        let latitudeDelta = (latitudes.max()! - latitudes.min()!) * 1.5 // 1.5 for padding
        let longitudeDelta = (longitudes.max()! - longitudes.min()!) * 1.5
        
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: max(latitudeDelta, 0.01),
                    longitudeDelta: max(longitudeDelta, 0.01)
                )
            ))
        }
    }
    
    private func startFriendsListener() {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        locationListener = db.collection("users")
            .whereField("friends", arrayContains: currentUserEmail)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error listening for friend updates: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    var updatedFriends: [Friend] = []
                    for document in documents {
                        let data = document.data()
                        let email = document.documentID
                        let displayName = data["displayName"] as? String ?? ""
                        let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue()
                        
                        // Try current location first, then fall back to last known location
                        let latitude = data["latitude"] as? Double ?? data["lastKnownLatitude"] as? Double
                        let longitude = data["longitude"] as? Double ?? data["lastKnownLongitude"] as? Double
                        let profileImageUrl = data["profileImageUrl"] as? String
                        
                        let location = (latitude.flatMap { lat in
                            longitude.flatMap { lon in
                                CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            }
                        })
                        
                        let friend = Friend(
                            email: email,
                            displayName: displayName,
                            location: location,
                            lastSeen: lastSeen,
                            lastKnownLocation: location, // Use the same location for both
                            profileImageUrl: profileImageUrl
                        )
                        updatedFriends.append(friend)
                    }
                    
                    withAnimation {
                        self.friends = updatedFriends.sorted { $0.displayName < $1.displayName }
                    }
                    self.isLoading = false
                    
                    // Update map region to show all friends
                    updateMapRegion()
                }
            }
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
                    if let firstLocation = friends.first?.bestAvailableLocation {
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
        HStack(spacing: 16) {
            // Left side - Profile Picture (now without online indicator)
            Group {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .onTapGesture {
                            profileTapAction()
                        }
                } else {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(friend.displayName.prefix(1).uppercased())
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.blue)
                        )
                        .onTapGesture {
                            profileTapAction()
                        }
                }
            }
            
            // Middle - Location Card
            Button(action: locationTapAction) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Text(locationName)
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        // Online status indicator moved here
                        HStack(spacing: 4) {
                            Circle()
                                .fill(friend.isOnline ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(friend.isOnline ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundColor(friend.isOnline ? .green : .gray)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Right side - Navigation
            if let location = friend.bestAvailableLocation {
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .onTapGesture {
                            openInGoogleMaps(location: location)
                        }
                    
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 24))
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .onAppear {
            loadProfileImage()
            if let location = friend.bestAvailableLocation {
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
    
    private func openInGoogleMaps(location: CLLocationCoordinate2D) {
        let urlString = "comgooglemaps://?daddr=\(location.latitude),\(location.longitude)&directionsmode=driving"
        
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url) { success in
                if !success {
                    openInBrowser(location: location)
                }
            }
        } else {
            openInBrowser(location: location)
        }
    }
    
    private func openInBrowser(location: CLLocationCoordinate2D) {
        let urlString = "https://www.google.com/maps/dir/?api=1&destination=\(location.latitude),\(location.longitude)&travelmode=driving"
        
        if let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encodedString) {
            UIApplication.shared.open(url)
        }
    }
}

// Profile Image Button Component
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




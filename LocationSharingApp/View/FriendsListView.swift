import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import MapKit
import FirebaseStorage

// Move Friend struct outside of FriendsListView to make it accessible to FriendRow
struct Friend: Identifiable {
    let id: String
    let email: String
    let displayName: String
    var location: CLLocationCoordinate2D?
    var lastSeen: Date?
    var profileImageUrl: String?
    
    var isOnline: Bool {
        guard let lastSeen = lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < 300 // 5 minutes
    }
}

struct FriendsListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var isLoading = true
    @State private var selectedFriend: Friend?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                Text("Friends")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            
            // Map View
            Map(position: .constant(.region(mapRegion))) {
                ForEach(friends) { friend in
                    if let location = friend.location {
                        Annotation(friend.displayName, coordinate: location) {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundColor(friend.isOnline ? .green : .gray)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .frame(height: 300)
            
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if friends.isEmpty {
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
            } else {
                List {
                    ForEach(friends) { friend in
                        FriendRow(friend: friend)
                            .onTapGesture {
                                if let location = friend.location {
                                    withAnimation {
                                        mapRegion.center = location
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            fetchFriends()
            startLocationListener()
        }
    }
    
    private func fetchFriends() {
        let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() ?? ""
        db.collection("users").document(currentUserEmail).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let friendsList = data["friends"] as? [String] {
                let group = DispatchGroup()
                var tempFriends: [Friend] = []
                
                for friendEmail in friendsList {
                    group.enter()
                    db.collection("users").document(friendEmail).getDocument { friendSnapshot, friendError in
                        if let friendData = friendSnapshot?.data(),
                           let displayName = friendData["displayName"] as? String {
                            let lastSeen = (friendData["lastSeen"] as? Timestamp)?.dateValue()
                            let latitude = friendData["latitude"] as? Double
                            let longitude = friendData["longitude"] as? Double
                            let profileImageUrl = friendData["profileImageUrl"] as? String
                            
                            var location: CLLocationCoordinate2D?
                            if let lat = latitude, let lon = longitude {
                                location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            }
                            
                            let friend = Friend(
                                id: friendEmail,
                                email: friendEmail,
                                displayName: displayName,
                                location: location,
                                lastSeen: lastSeen,
                                profileImageUrl: profileImageUrl
                            )
                            tempFriends.append(friend)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    friends = tempFriends.sorted { $0.displayName < $1.displayName }
                    if let firstLocation = friends.first?.location {
                        mapRegion.center = firstLocation
                    }
                    isLoading = false
                }
            } else {
                isLoading = false
            }
        }
    }
    
    private func startLocationListener() {
        let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() ?? ""
        db.collection("users").whereField("friends", arrayContains: currentUserEmail)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                for document in documents {
                    let data = document.data()
                    if let latitude = data["latitude"] as? Double,
                       let longitude = data["longitude"] as? Double,
                       let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue() {
                        
                        let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                        if let index = friends.firstIndex(where: { $0.email == document.documentID }) {
                            friends[index].location = location
                            friends[index].lastSeen = lastSeen
                        }
                    }
                }
            }
    }
}

struct FriendRow: View {
    let friend: Friend
    @State private var profileImage: UIImage?
    
    var body: some View {
        NavigationLink(destination: ProfileView(userEmail: friend.email, isCurrentUser: false)) {
            HStack(spacing: 12) {
                // Friend avatar
                if let image = profileImage {
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
                            Text(friend.displayName.prefix(1).uppercased())
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.blue)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.displayName)
                        .font(.system(size: 16, weight: .medium))
                    if let location = friend.location {
                        Text(formatLocation(location))
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Location status indicator
                Circle()
                    .fill(friend.isOnline ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            if let imageUrl = friend.profileImageUrl {
                loadProfileImage(from: imageUrl)
            }
        }
    }
    
    private func formatLocation(_ location: CLLocationCoordinate2D) -> String {
        let geocoder = CLGeocoder()
        var locationString = "Location updating..."
        
        geocoder.reverseGeocodeLocation(CLLocation(latitude: location.latitude, longitude: location.longitude)) { placemarks, error in
            if let placemark = placemarks?.first {
                if let locality = placemark.locality {
                    locationString = "In \(locality)"
                }
            }
        }
        
        return locationString
    }
    
    private func loadProfileImage(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.profileImage = image
                }
            }
        }.resume()
    }
}

struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        FriendsListView()
    }
}



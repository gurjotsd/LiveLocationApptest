import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pendingRequests: [FriendRequest] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    private let db = Firestore.firestore()
    
    struct FriendRequest: Identifiable, Sendable, Hashable {
        let id: String
        let email: String
        let displayName: String
        let profileImageUrl: String?
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: FriendRequest, rhs: FriendRequest) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.darkBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Search Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add Friend")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            // Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                TextField("Search by email", text: $searchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .foregroundColor(.white)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.cardBackground)
                            .cornerRadius(12)
                            .padding(.horizontal)
                            
                            // Send Request Button
                            if !searchText.isEmpty {
                                Button(action: {
                                    Task {
                                        await sendFriendRequest()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "person.badge.plus")
                                        Text("Send Friend Request")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                }
                                .padding(.horizontal)
                                .disabled(isProcessing)
                            }
                        }
                        
                        // Pending Requests Section
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if pendingRequests.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "person.2.circle")
                                    .font(.system(size: 64))
                                    .foregroundColor(.gray)
                                Text("No Pending Requests")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                Text("Friend requests will appear here")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pending Requests")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                
                                ForEach(pendingRequests) { request in
                                    RequestCard(
                                        request: request,
                                        onAccept: {
                                            await acceptRequest(request)
                                        },
                                        onDecline: {
                                            await declineRequest(request)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Friend Requests")
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            Task {
                await fetchPendingRequests()
            }
        }
    }
    
    private func fetchPendingRequests() async {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        do {
            let snapshot = try await db.collection("users").document(currentUserEmail).getDocument()
            
            guard let data = snapshot.data(),
                  let pendingRequests = data["pendingRequests"] as? [String] else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            var tempRequests: [FriendRequest] = []
            
            for requestEmail in pendingRequests {
                let requestSnapshot = try await db.collection("users").document(requestEmail).getDocument()
                if let requestData = requestSnapshot.data(),
                   let displayName = requestData["displayName"] as? String {
                    let request = FriendRequest(
                        id: requestEmail,
                        email: requestEmail,
                        displayName: displayName,
                        profileImageUrl: requestData["profileImageUrl"] as? String
                    )
                    tempRequests.append(request)
                }
            }
            
            await MainActor.run {
                self.pendingRequests = tempRequests.sorted { $0.displayName < $1.displayName }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error fetching requests: \(error.localizedDescription)"
                showAlert = true
                isLoading = false
            }
        }
    }
    
    private func acceptRequest(_ request: FriendRequest) async {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        do {
            let batch = db.batch()
            
            let currentUserUpdate: [String: Any] = [
                "friends": FieldValue.arrayUnion([request.email]),
                "pendingRequests": FieldValue.arrayRemove([request.email])
            ]
            
            let friendUpdate: [String: Any] = [
                "friends": FieldValue.arrayUnion([currentUserEmail])
            ]
            
            let currentUserRef = db.collection("users").document(currentUserEmail)
            let friendRef = db.collection("users").document(request.email)
            
            batch.updateData(currentUserUpdate, forDocument: currentUserRef)
            batch.updateData(friendUpdate, forDocument: friendRef)
            
            try await batch.commit()
            
            await MainActor.run {
                withAnimation {
                    pendingRequests.removeAll { $0.email == request.email }
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error accepting request: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func declineRequest(_ request: FriendRequest) async {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        do {
            let updateData: [String: Any] = [
                "pendingRequests": FieldValue.arrayRemove([request.email])
            ]
            
            try await db.collection("users").document(currentUserEmail).updateData(updateData)
            
            await MainActor.run {
                withAnimation {
                    pendingRequests.removeAll { $0.email == request.email }
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error declining request: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func sendFriendRequest() async {
        guard !isProcessing else { return }
        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }
        
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        let targetEmail = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            // Validate input
            guard !targetEmail.isEmpty else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please enter an email address"])
            }
            
            guard targetEmail != currentUserEmail else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You cannot send a friend request to yourself"])
            }
            
            // Check if user exists
            let snapshot = try await db.collection("users").document(targetEmail).getDocument()
            guard let userData = snapshot.data() else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
            }
            
            // Use type-safe dictionary access
            let friendsList = (userData["friends"] as? [String]) ?? []
            let pendingRequests = (userData["pendingRequests"] as? [String]) ?? []
            
            if friendsList.contains(currentUserEmail) {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "You are already friends with this user"])
            }
            
            if pendingRequests.contains(currentUserEmail) {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Friend request already sent"])
            }
            
            // Send friend request using a dictionary literal
            let updateData: [String: Any] = [
                "pendingRequests": FieldValue.arrayUnion([currentUserEmail])
            ]
            
            try await db.collection("users").document(targetEmail).updateData(updateData)
            
            await MainActor.run {
                alertMessage = "Friend request sent successfully"
                searchText = ""
                showAlert = true
            }
        } catch {
            await MainActor.run {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

// New RequestCard component
struct RequestCard: View {
    let request: RequestsView.FriendRequest
    let onAccept: () async -> Void
    let onDecline: () async -> Void
    @State private var profileImage: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile Image
            ProfileImageView(image: profileImage, displayName: request.displayName)
                .frame(width: 50, height: 50)
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(request.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                Text(request.email)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Action Buttons
            if !isLoading {
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            isLoading = true
                            await onDecline()
                            isLoading = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.2))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        Task {
                            isLoading = true
                            await onAccept()
                            isLoading = false
                        }
                    }) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                            .padding(8)
                            .background(Color.green.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct ProfileImageView: View {
    let image: UIImage?
    let displayName: String
    
    var body: some View {
        if let image = image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Text(displayName.prefix(1).uppercased())
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Color.gray)
                .clipShape(Circle())
        }
    }
} 

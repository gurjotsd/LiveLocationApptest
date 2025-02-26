import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [FriendRequest] = []
    @State private var isLoading = true
    @State private var searchEmail = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    private let db = Firestore.firestore()
    
    struct FriendRequest: Identifiable {
        let id: String
        let email: String
        let displayName: String
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                Text("Friend Requests")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            
            // Search bar
            HStack {
                TextField("Enter friend's email", text: $searchEmail)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                
                Button(action: sendFriendRequest) {
                    Text("Send")
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding()
            
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if requests.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    Text("No Pending Requests")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Add friends by entering their email above")
                        .foregroundColor(.gray)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(requests) { request in
                        RequestRowView(request: request, onAccept: {
                            acceptRequest(from: request.email)
                        }, onDecline: {
                            declineRequest(from: request.email)
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            fetchRequests()
        }
        .alert("Friend Request", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func fetchRequests() {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        db.collection("users").document(currentUserEmail).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let pendingRequests = data["pendingRequests"] as? [String] {
                
                let group = DispatchGroup()
                var tempRequests: [FriendRequest] = []
                
                for requestEmail in pendingRequests {
                    group.enter()
                    db.collection("users").document(requestEmail).getDocument { requestSnapshot, requestError in
                        if let requestData = requestSnapshot?.data(),
                           let displayName = requestData["displayName"] as? String {
                            let request = FriendRequest(
                                id: requestEmail,
                                email: requestEmail,
                                displayName: displayName
                            )
                            tempRequests.append(request)
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    requests = tempRequests.sorted { $0.displayName < $1.displayName }
                    isLoading = false
                }
            } else {
                isLoading = false
            }
        }
    }
    
    private func acceptRequest(from email: String) {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        // Add to friends list and remove from pending requests
        db.collection("users").document(currentUserEmail).updateData([
            "friends": FieldValue.arrayUnion([email]),
            "pendingRequests": FieldValue.arrayRemove([email])
        ])
        
        // Add current user to requester's friends list
        db.collection("users").document(email).updateData([
            "friends": FieldValue.arrayUnion([currentUserEmail])
        ])
        
        // Update local state
        requests.removeAll { $0.email == email }
    }
    
    private func declineRequest(from email: String) {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        // Remove from pending requests
        db.collection("users").document(currentUserEmail).updateData([
            "pendingRequests": FieldValue.arrayRemove([email])
        ])
        
        // Update local state
        requests.removeAll { $0.email == email }
    }
    
    private func sendFriendRequest() {
        guard let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        let targetEmail = searchEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !targetEmail.isEmpty else {
            alertMessage = "Please enter an email address"
            showAlert = true
            return
        }
        
        guard targetEmail != currentUserEmail else {
            alertMessage = "You cannot send a friend request to yourself"
            showAlert = true
            return
        }
        
        // Check if user exists and not already a friend
        db.collection("users").document(targetEmail).getDocument { snapshot, error in
            if let error = error {
                alertMessage = "Error: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            guard let userData = snapshot?.data() else {
                alertMessage = "User not found"
                showAlert = true
                return
            }
            
            let friendsList = userData["friends"] as? [String] ?? []
            let pendingRequests = userData["pendingRequests"] as? [String] ?? []
            
            if friendsList.contains(currentUserEmail) {
                alertMessage = "You are already friends with this user"
                showAlert = true
                return
            }
            
            if pendingRequests.contains(currentUserEmail) {
                alertMessage = "Friend request already sent"
                showAlert = true
                return
            }
            
            // Send friend request
            db.collection("users").document(targetEmail).updateData([
                "pendingRequests": FieldValue.arrayUnion([currentUserEmail])
            ]) { error in
                if let error = error {
                    alertMessage = "Error sending request: \(error.localizedDescription)"
                } else {
                    alertMessage = "Friend request sent successfully"
                    searchEmail = "" // Clear the search field
                }
                showAlert = true
            }
        }
    }
}

struct RequestRowView: View {
    let request: RequestsView.FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(request.displayName.prefix(1).uppercased())
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.displayName)
                    .font(.system(size: 16, weight: .medium))
                Text(request.email)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: onAccept) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                
                Button(action: onDecline) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
            }
        }
        .padding(.vertical, 8)
    }
} 

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// Model for a friend request document
struct FriendRequest: Identifiable {
    var id: String
    var sender: String
    var receiver: String
    var status: String
    var timestamp: Date?
}

struct FriendRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var friendRequests: [FriendRequest] = []
    @State private var isLoading: Bool = true
    @State private var newFriendEmail: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    private let db = Firestore.firestore()
    
    var currentUserEmail: String {
        Auth.auth().currentUser?.email?.lowercased() ?? ""
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
            
            // Send request section
            VStack(spacing: 16) {
                HStack {
                    TextField("Enter friend's email", text: $newFriendEmail)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: sendFriendRequest) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if friendRequests.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)
                    Text("No Pending Requests")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Friend requests you send or receive will appear here")
                        .foregroundColor(.gray)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(friendRequests) { request in
                        RequestRow(request: request, onAccept: {
                            acceptRequest(request)
                        }, onDecline: {
                            declineRequest(request)
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationBarHidden(true)
        .alert("Friend Request", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            fetchFriendRequests()
        }
    }
    
    private func sendFriendRequest() {
        guard !newFriendEmail.isEmpty else {
            print("Please enter a friend's email.")
            return
        }
        let senderEmail = currentUserEmail
        let receiverEmail = newFriendEmail.lowercased()
        
        FriendManager().sendFriendRequest(senderEmail: senderEmail, receiverEmail: receiverEmail) { success, message in
            print(message)
            if success {
                newFriendEmail = ""
                fetchFriendRequests() // Refresh the list if needed
            }
        }
    }
    
    private func fetchFriendRequests() {
        guard !currentUserEmail.isEmpty else {
            isLoading = false
            return
        }
        
        db.collection("friendRequests")
            .whereField("receiver", isEqualTo: currentUserEmail)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error fetching friend requests: \(error.localizedDescription)")
                    isLoading = false
                } else if let snapshot = snapshot {
                    friendRequests = snapshot.documents.map { doc in
                        let data = doc.data()
                        let sender = data["sender"] as? String ?? ""
                        let receiver = data["receiver"] as? String ?? ""
                        let status = data["status"] as? String ?? ""
                        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue()
                        return FriendRequest(id: doc.documentID, sender: sender, receiver: receiver, status: status, timestamp: timestamp)
                    }
                    isLoading = false
                }
            }
    }
    
    private func acceptRequest(_ request: FriendRequest) {
        FriendManager().acceptFriendRequest(docID: request.id, senderEmail: request.sender) { success, message in
            print(message)
        }
    }
    
    private func declineRequest(_ request: FriendRequest) {
        FriendManager().rejectFriendRequest(docID: request.id) { success, message in
            print(message)
        }
    }
}

struct RequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Request avatar
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundColor(.green)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.sender)
                    .font(.system(size: 16, weight: .medium))
                Text("Wants to be friends")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Accept/Decline buttons
            HStack(spacing: 8) {
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.2))
                        .clipShape(Circle())
                }
                
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .padding(8)
                        .background(Color.green.opacity(0.2))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

struct FriendRequestsView_Previews: PreviewProvider {
    static var previews: some View {
        FriendRequestsView()
    }
}

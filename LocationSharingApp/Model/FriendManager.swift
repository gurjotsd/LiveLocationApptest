import FirebaseFirestore
import FirebaseAuth

class FriendManager: ObservableObject {
    private let db = Firestore.firestore()
    
    // Send a friend request from the current user to another user
    func sendFriendRequest(senderEmail: String, receiverEmail: String, completion: @escaping (Bool, String) -> Void) {
        guard Auth.auth().currentUser != nil else {
            completion(false, "User not logged in.")
            return
        }
        
        let requestData: [String: Any] = [
            "sender": senderEmail.lowercased(),
            "receiver": receiverEmail.lowercased(),
            "status": "pending",
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        db.collection("friendRequests").addDocument(data: requestData) { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, "Friend request sent successfully.")
            }
        }
    }
    
    // Accept a friend request by updating its status and adding each user to the other's friend list
    func acceptFriendRequest(docID: String, senderEmail: String, completion: @escaping (Bool, String) -> Void) {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            completion(false, "User not logged in.")
            return
        }
        
        let requestRef = db.collection("friendRequests").document(docID)
        requestRef.updateData(["status": "accepted"]) { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                let currentUserRef = self.db.collection("users").document(currentUserEmail.lowercased())
                let senderRef = self.db.collection("users").document(senderEmail.lowercased())
                
                currentUserRef.updateData(["friends": FieldValue.arrayUnion([senderEmail.lowercased()])])
                senderRef.updateData(["friends": FieldValue.arrayUnion([currentUserEmail.lowercased()])])
                
                completion(true, "Friend request accepted successfully.")
            }
        }
    }
    
    // Reject a friend request by updating its status to "rejected"
    func rejectFriendRequest(docID: String, completion: @escaping (Bool, String) -> Void) {
        let requestRef = db.collection("friendRequests").document(docID)
        requestRef.updateData(["status": "rejected"]) { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, "Friend request rejected successfully.")
            }
        }
    }
}


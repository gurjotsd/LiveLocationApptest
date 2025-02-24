import FirebaseAuth
import Combine
import FirebaseFirestore
import FirebaseStorage

class SessionStore: ObservableObject {
    @Published var currentUser: User?
    @Published var authModel = AuthModel()
    private var handle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()
    
    init() {
        listenToAuthState()
    }
    
    func listenToAuthState() {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        
        // Add new listener
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Update auth state
                self.currentUser = user
                self.authModel.isLoggedIn = user != nil
                self.authModel.currentUserEmail = user?.email
                
                // If email was changed, update Firestore
                if let email = user?.email?.lowercased() {
                    self.updateUserEmailInFirestore(email: email)
                }
            }
        }
    }
    
    private func updateUserEmailInFirestore(email: String) {
        // Only update if user exists
        guard currentUser != nil else { return }
        
        db.collection("users").document(email).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("Error checking user document: \(error.localizedDescription)")
                return
            }
            
            // If document doesn't exist, it means email was changed
            if snapshot?.exists != true {
                // Update friends' references
                self?.updateFriendsReferences(newEmail: email)
            }
        }
    }
    
    private func updateFriendsReferences(newEmail: String) {
        // Update friends lists that contain the old email
        db.collection("users").whereField("friends", arrayContains: self.currentUser?.email ?? "")
            .getDocuments { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error getting documents: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                
                let batch = self?.db.batch()
                
                for doc in documents {
                    if let batch = batch {
                        let ref = self?.db.collection("users").document(doc.documentID)
                        if let ref = ref {
                            batch.updateData([
                                "friends": FieldValue.arrayRemove([self?.currentUser?.email ?? ""]),
                                "friends": FieldValue.arrayUnion([newEmail])
                            ], forDocument: ref)
                        }
                    }
                }
                
                batch?.commit { error in
                    if let error = error {
                        print("Error updating friends references: \(error.localizedDescription)")
                    }
                }
            }
    }
    
    func signIn(email: String, password: String, completion: @escaping (Bool, String) -> Void) {
        print("🔐 Attempting to sign in user: \(email)")
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                print("❌ Sign in failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("✅ User signed in successfully!")
                DispatchQueue.main.async {
                    self.authModel.isLoggedIn = true
                }
                completion(true, "Successfully signed in")
            }
        }
    }
    
    func signOut() {
        print("🚪 Attempting to sign out user")
        do {
            try Auth.auth().signOut()
            print("✅ User signed out successfully")
            DispatchQueue.main.async {
                self.currentUser = nil
                self.authModel.isLoggedIn = false
            }
        } catch {
            print("❌ Sign out failed: \(error.localizedDescription)")
        }
    }
    
    func signUp(email: String, password: String, displayName: String, profileImageData: Data? = nil, completion: @escaping (Error?) -> Void) {
        print("📝 Starting registration process for: \(email)")
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                print("❌ Registration failed: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            print("✅ User account created successfully")
            
            guard let userEmail = result?.user.email?.lowercased() else {
                print("❌ Failed to get user email")
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get user email"]))
                return
            }
            
            // Create user document in Firestore
            let userData: [String: Any] = [
                "email": userEmail,
                "displayName": displayName,
                "timestamp": FieldValue.serverTimestamp(),
                "friends": [],
                "pendingRequests": []
            ]
            
            print("📄 Creating Firestore document for user")
            
            self?.db.collection("users").document(userEmail).setData(userData) { error in
                if let error = error {
                    print("❌ Failed to create user document: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                
                print("✅ User document created successfully")
                
                if let imageData = profileImageData {
                    print("🖼️ Uploading profile picture")
                    self?.uploadProfileImage(imageData, for: userEmail) { error in
                        if let error = error {
                            print("⚠️ Profile picture upload failed: \(error.localizedDescription)")
                        } else {
                            print("✅ Profile picture uploaded successfully")
                        }
                        completion(error)
                    }
                } else {
                    print("ℹ️ No profile picture to upload")
                    completion(nil)
                }
            }
        }
    }
    
    private func uploadProfileImage(_ imageData: Data, for userEmail: String, completion: @escaping (Error?) -> Void) {
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("profile_images/\(userEmail).jpg")
        
        print("Uploading profile image to path: profile_images/\(userEmail).jpg")
        
        imageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                print("❌ Failed to upload image to Storage: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            print("✅ Image uploaded to Storage, getting download URL")
            
            imageRef.downloadURL { url, error in
                if let error = error {
                    print("❌ Failed to get download URL: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                
                guard let url = url else {
                    let error = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve image URL"])
                    print("❌ Error retrieving image URL: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                
                print("Got download URL: \(url.absoluteString)")
                // Update user profile with image URL
                self.db.collection("users").document(userEmail).updateData([
                    "profileImageUrl": url.absoluteString
                ]) { error in
                    if let error = error {
                        print("❌ Failed to update user document with image URL: \(error.localizedDescription)")
                        completion(error)
                    } else {
                        print("✅ Successfully updated user document with profile image URL")
                        completion(nil)
                    }
                }
            }
        }
    }
    
    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}


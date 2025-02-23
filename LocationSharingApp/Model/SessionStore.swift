import FirebaseAuth
import Combine
import FirebaseFirestore
import FirebaseStorage

class SessionStore: ObservableObject {
    @Published var currentUser: User?
    private var handle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()
    
    init() {
        listen()
    }
    
    func listen() {
        handle = Auth.auth().addStateDidChangeListener { auth, user in
            self.currentUser = user
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.currentUser = nil
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    func signUp(email: String, password: String, displayName: String, profileImageData: Data? = nil, completion: @escaping (Error?) -> Void) {
        print("Starting registration process for email: \(email)")
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                print("❌ Registration failed: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            print("✅ User successfully created in Firebase Auth")
            
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
            
            print("Creating Firestore document for user: \(userEmail)")
            
            self?.db.collection("users").document(userEmail).setData(userData) { error in
                if let error = error {
                    print("❌ Failed to create Firestore document: \(error.localizedDescription)")
                    completion(error)
                    return
                }
                
                print("✅ User document successfully created in Firestore")
                
                // If we have profile image data, upload it
                if let imageData = profileImageData {
                    print("Starting profile image upload")
                    self?.uploadProfileImage(imageData, for: userEmail) { error in
                        if let error = error {
                            print("❌ Profile image upload failed: \(error.localizedDescription)")
                            completion(error)
                            return
                        } else {
                            print("✅ Profile image successfully uploaded")
                        }
                        
                        // Continue to complete the sign-up after image upload
                        completion(nil)
                    }
                } else {
                    print("No profile image to upload")
                    // No image to upload, complete the sign-up process
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


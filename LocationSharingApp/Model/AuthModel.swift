import Foundation
import FirebaseAuth
import FirebaseFirestore

class AuthModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var currentUserEmail: String?
    private let db = Firestore.firestore()

    // Sign In Function
    func signIn(email: String, password: String, completion: @escaping (Bool, String) -> Void) {
        print("🔐 Attempting to sign in user: \(email)")
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                print("❌ Sign in failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("✅ User signed in successfully!")
                DispatchQueue.main.async {
                    self.isLoggedIn = true
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
                self.isLoggedIn = false
            }
        } catch {
            print("❌ Sign out failed: \(error.localizedDescription)")
        }
    }
    
    // Reset Password Function
    func resetPassword(email: String, completion: @escaping (Bool, String) -> Void) {
        print("🔑 Starting password reset for: \(email)")
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error {
                print("❌ Password reset failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            } else {
                print("✅ Password reset email sent successfully")
                completion(true, "Password reset email sent. Please check your inbox.")
            }
        }
    }

    func verifyEmailChange(newEmail: String, completion: @escaping (Bool, String) -> Void) {
        print("📧 Starting email change verification process")
        
        guard let user = Auth.auth().currentUser else {
            print("❌ No user logged in")
            completion(false, "No user logged in")
            return
        }
        
        guard newEmail.contains("@") && newEmail.contains(".") else {
            print("❌ Invalid email format")
            completion(false, "Please enter a valid email address")
            return
        }
        
        print("📤 Sending verification email to: \(newEmail)")
        user.sendEmailVerification(beforeUpdatingEmail: newEmail) { error in
            if let error = error {
                print("❌ Email verification failed: \(error.localizedDescription)")
                completion(false, "Error sending verification: \(error.localizedDescription)")
            } else {
                print("✅ Verification email sent successfully")
                completion(true, "Verification email sent. Please check your inbox to confirm the change.")
            }
        }
    }
    
    enum AuthError: LocalizedError {
        case notAuthenticated
        case userDataNotFound
        case emailUpdateFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "User not authenticated"
            case .userDataNotFound:
                return "User data not found"
            case .emailUpdateFailed(let message):
                return message
            }
        }
    }
}


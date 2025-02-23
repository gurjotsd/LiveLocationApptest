import Foundation
import FirebaseAuth

class AuthModel: ObservableObject {
    @Published var isLoggedIn = false

    // Sign In Function
    func signIn(email: String, password: String, completion: @escaping (Bool, String) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                DispatchQueue.main.async {
                    self.isLoggedIn = true
                }
                completion(true, "User authenticated successfully")
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            DispatchQueue.main.async {
                self.isLoggedIn = false
            }
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    // Reset Password Function
    func resetPassword(email: String, completion: @escaping (Bool, String) -> Void) {
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error {
                completion(false, error.localizedDescription)
            } else {
                completion(true, "Password reset email sent. Please check your inbox.")
            }
        }
    }
}


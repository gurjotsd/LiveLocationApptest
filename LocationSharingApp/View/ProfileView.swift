import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import PhotosUI
import FirebaseStorage

extension Color {
    static let darkBackground = Color(hex: "1A1A1A")
    static let cardBackground = Color(hex: "3A3A3A")
}

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: SessionStore
    @State private var userData: UserProfile?
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var editedDisplayName = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showingEmailChange = false
    @State private var showingPasswordReset = false
    @State private var newEmail = ""
    let userEmail: String
    let isCurrentUser: Bool
    private let db = Firestore.firestore()
    
    struct UserProfile {
        let email: String
        let displayName: String
        let joinDate: Date?
        var profileImageUrl: String?
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "1a1a1a"), Color(hex: "2d2d2d")]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom nav bar with blur effect
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text(isCurrentUser ? "My Profile" : "Profile")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Spacer()
                    if isCurrentUser {
                        Button(action: { isEditing.toggle() }) {
                            Text(isEditing ? "Done" : "Edit")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if let profile = userData {
                    ScrollView {
                        VStack(spacing: 35) {
                            // Profile Image with glow effect
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 130, height: 130)
                                    .blur(radius: 10)
                                
                                if isEditing {
                                    PhotosPicker(selection: $selectedItem) {
                                        profileImageView
                                            .overlay(
                                                Circle()
                                                    .fill(Color.black.opacity(0.5))
                                                    .overlay(
                                                        Image(systemName: "camera.fill")
                                                            .foregroundColor(.white)
                                                            .font(.system(size: 24))
                                                    )
                                            )
                                    }
                                } else {
                                    profileImageView
                                }
                            }
                            
                            // Profile Info Card
                            VStack(spacing: 20) {
                                if isEditing {
                                    TextField("Display Name", text: $editedDisplayName)
                                        .textFieldStyle(ModernTextFieldStyle())
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 250)
                                } else {
                                    Text(profile.displayName)
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                }
                                
                                Text(profile.email)
                                    .foregroundColor(.gray)
                                
                                if let date = profile.joinDate {
                                    Text("Joined \(date.formatted(.dateTime.month().year()))")
                                        .font(.subheadline)
                                        .foregroundColor(.gray.opacity(0.8))
                                }
                            }
                            .padding(.vertical)
                            
                            if isCurrentUser {
                                // Settings Section
                                VStack(spacing: 16) {
                                    if isEditing {
                                        GlowingButton(
                                            title: "Change Email",
                                            icon: "envelope.fill",
                                            color: .blue
                                        ) {
                                            showingEmailChange = true
                                        }
                                        
                                        GlowingButton(
                                            title: "Reset Password",
                                            icon: "lock.fill",
                                            color: .purple
                                        ) {
                                            showingPasswordReset = true
                                        }
                                        
                                        if isEditing {
                                            Button(action: saveProfile) {
                                                Text("Save Changes")
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding()
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 14)
                                                            .fill(Color.blue)
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 14)
                                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                            )
                                                    )
                                                    .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 2)
                                            }
                                        }
                                    }
                                    
                                    if !isEditing {
                                        Button(action: {
                                            session.signOut()
                                            dismiss()
                                        }) {
                                            HStack {
                                                Image(systemName: "arrow.right.circle")
                                                Text("Logout")
                                            }
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(Color.red.opacity(0.2))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14)
                                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                                    )
                                            )
                                            .shadow(color: Color.red.opacity(0.2), radius: 5, x: 0, y: 2)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 30)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Change Email", isPresented: $showingEmailChange) {
            TextField("New Email", text: $newEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            Button("Cancel", role: .cancel) {
                newEmail = ""
            }
            Button("Send Verification") {
                sendEmailChangeVerification()
            }
        } message: {
            Text("A verification email will be sent to confirm this change")
        }
        .alert("Reset Password", isPresented: $showingPasswordReset) {
            Button("Cancel", role: .cancel) { }
            Button("Send Reset Link") {
                resetPassword()
            }
        } message: {
            Text("A password reset link will be sent to your email address")
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            fetchUserProfile()
        }
        .onChange(of: selectedItem, initial: false) { oldValue, newValue in
            if let newValue {
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            print("🖼️ New profile image selected")
                            profileImage = uiImage
                            uploadProfileImage(uiImage)
                        }
                    } else {
                        print("❌ Failed to load selected image")
                    }
                }
            }
        }
    }
    
    private var profileImageView: some View {
        Group {
            if let image = profileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.cardBackground)
                    .overlay(
                        Text(userData?.displayName.prefix(1).uppercased() ?? "")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white)
                    )
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 2)
        )
    }
    
    private func fetchUserProfile() {
        print("📥 Fetching user profile...")
        db.collection("users").document(userEmail).getDocument { snapshot, error in
            if let error = error {
                print("❌ Failed to fetch profile: \(error.localizedDescription)")
                isLoading = false
                return
            }
            
            if let data = snapshot?.data(),
               let displayName = data["displayName"] as? String {
                print("✅ Profile fetched successfully!")
                let joinDate = (data["timestamp"] as? Timestamp)?.dateValue()
                let imageUrl = data["profileImageUrl"] as? String
                
                userData = UserProfile(
                    email: userEmail,
                    displayName: displayName,
                    joinDate: joinDate,
                    profileImageUrl: imageUrl
                )
                editedDisplayName = displayName
                
                if let imageUrl = imageUrl {
                    print("🖼️ Loading profile image...")
                    loadProfileImage(from: imageUrl)
                }
            } else {
                print("⚠️ No profile data found")
            }
            isLoading = false
        }
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
    
    private func uploadProfileImage(_ image: UIImage) {
        print("📸 Starting profile image upload...")
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            print("❌ Failed to convert image to data")
            return
        }
        
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("profile_images/\(userEmail).jpg")
        
        imageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                print("❌ Image upload failed: \(error.localizedDescription)")
                alertMessage = "Error uploading image: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            print("✅ Image uploaded successfully, getting download URL...")
            imageRef.downloadURL { url, error in
                if let error = error {
                    print("❌ Failed to get download URL: \(error.localizedDescription)")
                    alertMessage = "Error getting download URL: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
                
                if let url = url {
                    print("📝 Updating Firestore with new image URL...")
                    db.collection("users").document(userEmail).updateData([
                        "profileImageUrl": url.absoluteString
                    ]) { error in
                        if let error = error {
                            print("❌ Failed to update profile in Firestore: \(error.localizedDescription)")
                            alertMessage = "Error updating profile: \(error.localizedDescription)"
                        } else {
                            print("✅ Profile image updated successfully!")
                            alertMessage = "Profile image updated successfully"
                            userData?.profileImageUrl = url.absoluteString
                            loadProfileImage(from: url.absoluteString)
                        }
                        showAlert = true
                    }
                }
            }
        }
    }
    
    private func saveProfile() {
        print("📝 Starting profile update...")
        let trimmedName = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            print("❌ Display name is empty")
            alertMessage = "Display name cannot be empty"
            showAlert = true
            return
        }
        
        print("📝 Updating display name in Firestore...")
        db.collection("users").document(userEmail).updateData([
            "displayName": trimmedName
        ]) { error in
            if let error = error {
                print("❌ Failed to update display name: \(error.localizedDescription)")
                alertMessage = "Error updating profile: \(error.localizedDescription)"
            } else {
                print("✅ Display name updated successfully!")
                alertMessage = "Profile updated successfully"
                fetchUserProfile()
            }
            showAlert = true
            isEditing = false
        }
    }
    
    private func resetPassword() {
        print("🔑 Sending password reset email...")
        Auth.auth().sendPasswordReset(withEmail: userEmail) { error in
            if let error = error {
                print("❌ Password reset failed: \(error.localizedDescription)")
                alertMessage = "Error sending reset link: \(error.localizedDescription)"
            } else {
                print("✅ Password reset email sent successfully!")
                alertMessage = "Password reset link sent to your email"
            }
            showAlert = true
        }
    }
    
    private func sendEmailChangeVerification() {
        print("📧 Starting email change verification...")
        let trimmedEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        session.authModel.verifyEmailChange(newEmail: trimmedEmail) { success, message in
            DispatchQueue.main.async {
                if success {
                    print("✅ Email verification sent successfully!")
                    self.newEmail = ""
                    self.showingEmailChange = false
                } else {
                    print("❌ Email verification failed: \(message)")
                }
                self.alertMessage = message
                self.showAlert = true
            }
        }
    }
}

// Custom Components
struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "2d2d2d"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
    }
}

struct GlowingButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "2d2d2d"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(color.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: color.opacity(0.2), radius: 5, x: 0, y: 2)
        }
    }
} 

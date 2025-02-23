import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import PhotosUI
import FirebaseStorage

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
    @State private var profileImageUrl: String?
    @State private var profileImage: UIImage?
    
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
        VStack(spacing: 0) {
            // Custom navigation bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                Text(isCurrentUser ? "My Profile" : "Profile")
                    .font(.system(size: 18, weight: .semibold))
                if isCurrentUser {
                    Spacer()
                    Button(action: { isEditing.toggle() }) {
                        Text(isEditing ? "Done" : "Edit")
                    }
                } else {
                    Spacer()
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if let profile = userData {
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Avatar
                        if isEditing {
                            PhotosPicker(selection: $selectedItem) {
                                profileImageView
                                    .overlay(
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.title)
                                            .foregroundColor(.blue)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                            .offset(x: 30, y: 30)
                                    )
                            }
                        } else {
                            profileImageView
                        }
                        
                        // Profile Info
                        VStack(spacing: 8) {
                            if isEditing {
                                TextField("Display Name", text: $editedDisplayName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .padding(.horizontal)
                            } else {
                                Text(profile.displayName)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            
                            Text(profile.email)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        if isCurrentUser && !isEditing {
                            Button(action: {
                                session.signOut()
                                dismiss()
                            }) {
                                Label("Logout", systemImage: "arrow.right.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                        
                        if isEditing {
                            Button(action: saveProfile) {
                                Label("Save Changes", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            fetchUserProfile()
        }
        .onChange(of: selectedItem, initial: false) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async {
                        profileImage = uiImage
                        uploadProfileImage(uiImage)
                    }
                }
            }
        }
        .alert("Profile Update", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
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
                    .fill(Color.blue.opacity(0.2))
                    .overlay(
                        Text(userData?.displayName.prefix(1).uppercased() ?? "")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.blue)
                    )
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
    }
    
    private func fetchUserProfile() {
        db.collection("users").document(userEmail).getDocument { snapshot, error in
            if let data = snapshot?.data(),
               let displayName = data["displayName"] as? String {
                let joinDate = (data["timestamp"] as? Timestamp)?.dateValue()
                let imageUrl = data["profileImageUrl"] as? String
                
                userData = UserProfile(
                    email: userEmail,
                    displayName: displayName,
                    joinDate: joinDate,
                    profileImageUrl: imageUrl
                )
                editedDisplayName = displayName
                
                // Load profile image if URL exists
                if let imageUrl = imageUrl {
                    loadProfileImage(from: imageUrl)
                }
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
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }
        let storageRef = Storage.storage().reference()
        let imageRef = storageRef.child("profile_images/\(userEmail).jpg")
        
        imageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                alertMessage = "Error uploading image: \(error.localizedDescription)"
                showAlert = true
                return
            }
            
            imageRef.downloadURL { url, error in
                if let error = error {
                    alertMessage = "Error getting download URL: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
                
                if let url = url {
                    // Update Firestore with the new image URL
                    db.collection("users").document(userEmail).updateData([
                        "profileImageUrl": url.absoluteString
                    ]) { error in
                        if let error = error {
                            alertMessage = "Error updating profile: \(error.localizedDescription)"
                        } else {
                            alertMessage = "Profile updated successfully"
                            profileImageUrl = url.absoluteString
                            loadProfileImage(from: url.absoluteString)
                        }
                        showAlert = true
                    }
                }
            }
        }
    }
    
    private func saveProfile() {
        guard !editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Display name cannot be empty"
            showAlert = true
            return
        }
        
        db.collection("users").document(userEmail).updateData([
            "displayName": editedDisplayName
        ]) { error in
            if let error = error {
                alertMessage = "Error updating profile: \(error.localizedDescription)"
            } else {
                alertMessage = "Profile updated successfully"
                fetchUserProfile()
            }
            showAlert = true
            isEditing = false
        }
    }
} 

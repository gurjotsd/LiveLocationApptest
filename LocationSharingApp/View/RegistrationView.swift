import SwiftUI
import PhotosUI
import FirebaseStorage

struct RegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Modern dark gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "1A1A1A"), // Dark grey
                    Color(hex: "2D2D2D")  // Slightly lighter grey
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 35) {
                    // Back button and title
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Text("Create Account")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // Profile Image Picker
                    VStack(spacing: 12) {
                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            if let profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                    )
                            } else {
                                Circle()
                                    .fill(Color(hex: "3A3A3A"))
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.3))
                                    )
                            }
                        }
                        
                        Text("Add Profile Picture")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 20)
                    
                    // Input fields
                    VStack(spacing: 20) {
                        // Display name field
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.6))
                            TextField("Display Name", text: $displayName)
                                .foregroundColor(.white)
                                .tint(.white)
                        }
                        .padding()
                        .background(Color(hex: "3A3A3A"))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        
                        // Email field
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.white.opacity(0.6))
                            TextField("Email", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .foregroundColor(.white)
                                .tint(.white)
                        }
                        .padding()
                        .background(Color(hex: "3A3A3A"))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        
                        // Password field
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.white.opacity(0.6))
                            SecureField("Password", text: $password)
                                .foregroundColor(.white)
                                .tint(.white)
                        }
                        .padding()
                        .background(Color(hex: "3A3A3A"))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Sign up button
                    Button(action: handleSignUp) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .frame(width: 20, height: 20)
                        } else {
                            Text("Create Account")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "4A4A4A"), Color(hex: "3A3A3A")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
                .padding(.vertical, 20)
            }
            .navigationBarHidden(true)
        }
        .onChange(of: selectedItem, initial: false) { oldValue, newValue in
            Task {
                do {
                    if let data = try await newValue?.loadTransferable(type: Data.self) {
                        if let uiImage = UIImage(data: data) {
                            await MainActor.run {
                                profileImage = uiImage
                                print("✅ Profile image successfully loaded")
                            }
                        }
                    }
                } catch {
                    print("❌ Error loading image: \(error)")
                    await MainActor.run {
                        alertMessage = "Failed to load image"
                        showAlert = true
                    }
                }
            }
        }
        .alert("Registration Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func handleSignUp() {
        isLoading = true
        
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter a display name"
            showAlert = true
            isLoading = false
            return
        }
        
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Please enter an email"
            showAlert = true
            isLoading = false
            return
        }
        
        guard !password.isEmpty else {
            alertMessage = "Please enter a password"
            showAlert = true
            isLoading = false
            return
        }
        
        let imageData = profileImage?.jpegData(compressionQuality: 0.7)
        
        session.signUp(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            profileImageData: imageData
        ) { error in
            isLoading = false
            if let error = error {
                alertMessage = error.localizedDescription
                showAlert = true
            } else {
                dismiss()
            }
        }
    }
}


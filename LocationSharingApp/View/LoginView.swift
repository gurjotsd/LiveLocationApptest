import SwiftUI

struct AlertData: Identifiable {
    let id = UUID()
    let message: String
}

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var authModel = AuthModel()
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var alertData: AlertData? = nil
    @State private var navigateToHome = false
    
    var body: some View {
        NavigationStack {
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
                
                VStack(spacing: 35) {
                    // App logo/title
                    VStack(spacing: 12) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.linearGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        
                        Text("Location Sharing")
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.bottom, 50)
                    
                    // Input fields
                    VStack(spacing: 20) {
                        // Email field
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.white.opacity(0.6))
                            TextField("Email", text: $username)
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
                    
                    // Login button
                    Button(action: {
                        authModel.signIn(email: username, password: password) { success, message in
                            if success {
                                navigateToHome = true
                            } else {
                                alertData = AlertData(message: message)
                            }
                        }
                    }) {
                        Text("Sign In")
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
                    .padding(.horizontal)
                    
                    // Bottom buttons
                    VStack(spacing: 16) {
                        Button(action: {
                            if username.isEmpty {
                                alertData = AlertData(message: "Please enter your email address.")
                            } else {
                                authModel.resetPassword(email: username) { success, message in
                                    alertData = AlertData(message: message)
                                }
                            }
                        }) {
                            Text("Forgot Password?")
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        NavigationLink("Don't have an account? Sign up", destination: RegistrationView())
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.vertical, 40)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToHome) {
                HomeView()
            }
            .onAppear {
                username = ""
                password = ""
            }
            .alert(item: $alertData) { data in
                Alert(
                    title: Text("Alert"),
                    message: Text(data.message),
                    dismissButton: .default(Text("OK"), action: {
                        alertData = nil
                    })
                )
            }
        }
    }
}

// Helper for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


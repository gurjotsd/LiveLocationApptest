import Foundation
import CoreLocation
import MapKit
import FirebaseFirestore
import FirebaseAuth

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()

    @Published var region: MKCoordinateRegion?
    @Published var isAuthorized: Bool = false // Tracks authorization status

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update location every 10 meters
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.checkLocationPermission()
        }
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func checkLocationPermission() {
        let authStatus = locationManager.authorizationStatus
        DispatchQueue.main.async {
            switch authStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.isAuthorized = true
                self.locationManager.startUpdatingLocation()
            case .denied, .restricted:
                self.isAuthorized = false
                print("❌ Location access denied.")
            case .notDetermined:
                self.requestLocationPermission()
            @unknown default:
                break
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationPermission()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              let currentUserEmail = Auth.auth().currentUser?.email?.lowercased() else { return }
        
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        
        // Update user's location in Firestore
        let db = Firestore.firestore()
        db.collection("users").document(currentUserEmail).updateData([
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "lastKnownLatitude": location.coordinate.latitude,
            "lastKnownLongitude": location.coordinate.longitude,
            "lastSeen": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Error updating location: \(error.localizedDescription)")
            }
        }
    }
}


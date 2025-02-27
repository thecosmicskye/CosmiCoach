import Foundation
import CoreLocation
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var locationAccessGranted = false
    @Published var currentLocation: CLLocation?
    @Published var lastLocationUpdate: Date?
    
    // Provide a formatted description of the current location
    var locationDescription: String? {
        guard let location = currentLocation else { return nil }
        
        // Using reverse geocoding to get a human-readable address
        let geocoder = CLGeocoder()
        var result: String?
        
        let semaphore = DispatchSemaphore(value: 0)
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            defer { semaphore.signal() }
            
            if let error = error {
                print("Reverse geocoding error: \(error.localizedDescription)")
                result = "Location: \(location.coordinate.latitude), \(location.coordinate.longitude)"
                return
            }
            
            if let placemark = placemarks?.first {
                var components: [String] = []
                
                if let name = placemark.name {
                    components.append(name)
                }
                
                if let thoroughfare = placemark.thoroughfare {
                    if !components.contains(thoroughfare) {
                        components.append(thoroughfare)
                    }
                }
                
                if let locality = placemark.locality {
                    components.append(locality)
                }
                
                if let administrativeArea = placemark.administrativeArea {
                    components.append(administrativeArea)
                }
                
                result = components.joined(separator: ", ")
            } else {
                result = "Location: \(location.coordinate.latitude), \(location.coordinate.longitude)"
            }
        }
        
        // Wait with a timeout for geocoding to complete
        _ = semaphore.wait(timeout: .now() + 2.0)
        return result
    }
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        checkPermissions()
    }
    
    func checkPermissions() {
        let status = locationManager.authorizationStatus
        locationAccessGranted = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }
    
    func requestAccess() {
        print("📍 Requesting location authorization")
        locationManager.requestWhenInUseAuthorization()
        // Always start updates when requesting access - this is needed for permission prompt to show
        locationManager.startUpdatingLocation()
    }
    
    func startUpdatingLocation() {
        if locationAccessGranted {
            locationManager.startUpdatingLocation()
        }
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate methods
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkPermissions()
        if locationAccessGranted && UserDefaults.standard.bool(forKey: "enable_location_awareness") {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location
            lastLocationUpdate = Date()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
}

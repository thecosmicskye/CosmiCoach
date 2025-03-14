import Foundation
import CoreLocation
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var locationAccessGranted = false
    @Published var currentLocation: CLLocation?
    @Published var lastLocationUpdate: Date?
    
    // Provide a formatted description of the current location asynchronously
    func getLocationDescription() async -> String? {
        guard let location = currentLocation else { return nil }
        
        // Using reverse geocoding to get a human-readable address
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
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
                
                return components.joined(separator: ", ")
            } else {
                return "Location: \(location.coordinate.latitude), \(location.coordinate.longitude)"
            }
        } catch {
            print("Reverse geocoding error: \(error.localizedDescription)")
            return "Location: \(location.coordinate.latitude), \(location.coordinate.longitude)"
        }
    }
    
    // Legacy synchronous property for backward compatibility
    // Note: This will be deprecated in future versions
    var locationDescription: String? {
        guard let location = currentLocation else { return nil }
        return "Location: \(location.coordinate.latitude), \(location.coordinate.longitude)"
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

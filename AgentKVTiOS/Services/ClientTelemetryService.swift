import Foundation
import CoreLocation
import EventKit

class ClientTelemetryService: NSObject, CLLocationManagerDelegate {
    static let shared = ClientTelemetryService()
    
    private let locationManager = CLLocationManager()
    private let eventStore = EKEventStore()
    
    private var currentLocation: CLLocation?
    private var isLocationReady: ((CLLocation?) -> Void)?
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestCalendarPermission() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await eventStore.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }
    
    private func fetchCurrentLocation() async -> CLLocation? {
        guard locationManager.authorizationStatus == .authorizedAlways || 
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            self.isLocationReady = { location in
                continuation.resume(returning: location)
            }
            locationManager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        isLocationReady?(locations.last)
        isLocationReady = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocationReady?(nil)
        isLocationReady = nil
    }
    
    private func fetchEvents48h() -> [[String: Any]] {
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        guard authStatus == .authorized || authStatus == .fullAccess else { return [] }
        
        let startDate = Date().addingTimeInterval(-3600) // 1 hr ago
        let endDate = Date().addingTimeInterval(48 * 3600) // +48 hrs
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        
        let events = eventStore.events(matching: predicate)
        return events.map { event in
            [
                "id": event.eventIdentifier ?? UUID().uuidString,
                "title": event.title ?? "Event",
                "start_at": ISO8601DateFormatter().string(from: event.startDate),
                "end_at": ISO8601DateFormatter().string(from: event.endDate),
                "location": event.location ?? ""
            ]
        }
    }
    
    func buildSnapshotPayload() async -> [String: Any] {
        var payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let loc = await fetchCurrentLocation() {
            payload["location"] = [
                "latitude": loc.coordinate.latitude,
                "longitude": loc.coordinate.longitude
            ]
            // We could also do geocoding here to get 'locality' and 'administrative_area'
        }
        
        // Placeholder for WeatherKit which requires additional setup/entitlements
        payload["weather"] = [
            "condition": "unavailable",
            "temperature_celsius": 0
        ]
        
        payload["events_48h"] = fetchEvents48h()
        return payload
    }
}

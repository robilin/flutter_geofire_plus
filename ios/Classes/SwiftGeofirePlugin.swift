import Flutter
import UIKit
import CoreLocation
import GeoFire
import FirebaseDatabase


public class SwiftGeofirePlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate {
    static let pendingWritesKey = "flutter_geofire_pending_writes"
    static var persistenceConfigured = false

    
    var geoFireRef:DatabaseReference?
    var geoFire:GeoFire?
    private var eventSink: FlutterEventSink?
    var circleQuery : GFCircleQuery?
    private var locationManager: CLLocationManager?
    private var nativeTrackingId: String?
    private var nativeTrackingData: [String: Any] = [:]
    private var nativeTrackingDistance: CLLocationDistance = 20
    private var nativeTrackingIntervalMs: Double = 10000
    private var nativeTrackingIncludeLocationMeta = true
    private var nativeTrackingRunning = false
    private var nativeTrackingAllowBackground = false
    private var nativeTrackingUseSignificantChanges = false
    private var nativeLastPushAtMs: Double = 0

    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "geofire", binaryMessenger: registrar.messenger())
    let instance = SwiftGeofirePlugin()

    let eventChannel = FlutterEventChannel(name: "geofireStream",
                                                  binaryMessenger: registrar.messenger())
    
    
    
    
    eventChannel.setStreamHandler(instance)
    
    registrar.addMethodCallDelegate(instance, channel: channel)
    
    
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    
    var key = [String]()
    
    let arguements = call.arguments as? NSDictionary
    
    if(call.method.elementsEqual("GeoFire.start")){

        configurePersistenceIfNeeded()
     
        let path = arguements!["path"] as! String
        
        geoFireRef = Database.database().reference().child(path)
        geoFire = GeoFire(firebaseRef: geoFireRef!)
        flushPendingWrites()
        
        result(true)
    }
    
    else if(call.method.elementsEqual("setLocation")){
        
        let id = arguements!["id"] as! String
        let lat = arguements!["lat"] as! Double
        let lng = arguements!["lng"] as! Double

        let request = createWriteRequest(id: id, lat: lat, lng: lng, data: [:])
        enqueuePendingWrite(request)

        writeLocationWithData(request) { isSuccess in
            if isSuccess {
                self.dequeuePendingWrite(request["requestId"] as! String)
                result(true)
            } else {
                result(false)
            }
        }
    
    }

    else if(call.method.elementsEqual("setLocationWithData") || call.method.elementsEqual("setLocationWithMetadata")){
        let id = arguements!["id"] as! String
        let lat = arguements!["lat"] as! Double
        let lng = arguements!["lng"] as! Double
        let data = arguements!["data"] as? [String: Any] ?? [:]
        let sanitized = self.sanitizeAdditionalData(data)
        let request = createWriteRequest(id: id, lat: lat, lng: lng, data: sanitized)

        enqueuePendingWrite(request)

        writeLocationWithData(request) { isSuccess in
            if isSuccess {
                self.dequeuePendingWrite(request["requestId"] as! String)
                result(true)
            } else {
                result(false)
            }
        }
    }
    
    else if(call.method.elementsEqual("removeLocation")){
        
        let id = arguements!["id"] as! String
        

        geoFire?.removeKey(id) { (error) in
            if (error != nil) {
                print("An error occured: \(String(describing: error))")
                result("An error occured: \(String(describing: error))")
                
            } else {
                print("Removed location successfully!")
                result(true)
            }
        }
        
    }
    else if(call.method.elementsEqual("stopListener")){
        
        circleQuery?.removeAllObservers()
        
        result(true);
        
    }

    else if(call.method.elementsEqual("startNativeTracking")){
        let response = startNativeTrackingDetailed(arguments: arguements)
        result(response["started"] as? Bool ?? false)
    }

    else if(call.method.elementsEqual("startNativeTrackingDetailed")){
        result(startNativeTrackingDetailed(arguments: arguements))
    }

    else if(call.method.elementsEqual("stopNativeTracking")){
        stopNativeTracking()
        result(true)
    }

    else if(call.method.elementsEqual("nativeTrackingStatus")){
        result(nativeTrackingStatus())
    }
    
    else if(call.method.elementsEqual("getLocation")){
        
        let id = arguements!["id"] as! String
        
        
        geoFire?.getLocationForKey(id) { (location, error) in
            if (error != nil) {
                print("An error occurred getting the location for \(id): \(String(describing: error?.localizedDescription))")
            } else if (location != nil) {
                print("Location for \(id) is [\(String(describing: location?.coordinate.latitude)), \(location?.coordinate.longitude)]")
                
                var param=[String:AnyObject]()
                param["lat"]=location?.coordinate.latitude as AnyObject
                param["lng"]=location?.coordinate.longitude as AnyObject
                
                result(param)
                
            } else {
                
                var param=[String:AnyObject]()
                param["error"] = "GeoFire does not contain a location for \(id)" as AnyObject
            
                
                result(param)
                
                print("GeoFire does not contain a location for \"firebase-hq\"")
            }
        }
        
        
    }
    
    
    if(call.method.elementsEqual("queryAtLocation")){
        
        
        let lat = arguements!["lat"] as! Double
        let lng = arguements!["lng"] as! Double
        let radius = arguements!["radius"] as! Double
        let includeData = arguements?["includeData"] as? Bool ?? false
        
        
        let location:CLLocation = CLLocation(latitude: CLLocationDegrees(lat), longitude: CLLocationDegrees(lng))
        
        circleQuery = geoFire?.query(at: location, withRadius: radius)
        
        _ = circleQuery?.observe(.keyEntered, with: { (parkingKey, location) in
            key.append(parkingKey)
            print("Key is \(parkingKey)")
            self.emitQueryEventWithData(callBack: "onKeyEntered", key: parkingKey, location: location, includeData: includeData)
            
        })
        
        _ = circleQuery?.observe(.keyMoved, with: { (parkingKey, location) in
            key.append(parkingKey)
            print("Key is \(parkingKey)")
            self.emitQueryEventWithData(callBack: "onKeyMoved", key: parkingKey, location: location, includeData: includeData)
            
        })
        
        _ = circleQuery?.observe(.keyExited, with: { (parkingKey, location) in
            self.emitQueryEventWithData(callBack: "onKeyExited", key: parkingKey, location: location, includeData: includeData)
            
        })
        
        
        circleQuery?.observeReady {
            
            var param=[String:Any]()
            
            param["callBack"] = "onGeoQueryReady"
            param["result"] = key
            self.eventSink!(param)
            
        }
    }
    
  }

    private func startNativeTrackingDetailed(arguments: NSDictionary?) -> [String: Any] {
        guard CLLocationManager.locationServicesEnabled() else {
            return buildNativeTrackingStartResponse(started: false, reason: "location_services_disabled")
        }

        guard geoFire != nil else {
            return buildNativeTrackingStartResponse(started: false, reason: "not_initialized")
        }

        guard let id = arguments?["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return buildNativeTrackingStartResponse(started: false, reason: "invalid_id")
        }

        nativeTrackingId = id
        nativeTrackingIntervalMs = max(1000, (arguments?["intervalMs"] as? NSNumber)?.doubleValue ?? 10000)
        nativeTrackingDistance = max(0, (arguments?["minDistanceMeters"] as? NSNumber)?.doubleValue ?? 20)
        nativeTrackingIncludeLocationMeta = arguments?["includeLocationMeta"] as? Bool ?? true
        nativeTrackingAllowBackground = arguments?["allowBackground"] as? Bool ?? false
        nativeTrackingUseSignificantChanges = arguments?["useSignificantChanges"] as? Bool ?? false
        nativeLastPushAtMs = 0
        nativeTrackingData = Dictionary(uniqueKeysWithValues: sanitizeAdditionalData(arguments?["data"] as? [String: Any] ?? [:]).map {
            (String(describing: $0.key), $0.value)
        })

        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
        }

        guard let manager = locationManager else {
            return buildNativeTrackingStartResponse(started: false, reason: "location_manager_unavailable")
        }

        stopNativeTracking()

        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = nativeTrackingDistance
        manager.pausesLocationUpdatesAutomatically = false

        if #available(iOS 9.0, *) {
            manager.allowsBackgroundLocationUpdates = nativeTrackingAllowBackground
        }

        switch CLLocationManager.authorizationStatus() {
        case .notDetermined:
            if nativeTrackingAllowBackground {
                manager.requestAlwaysAuthorization()
            } else {
                manager.requestWhenInUseAuthorization()
            }
            return buildNativeTrackingStartResponse(started: false, reason: "authorization_request_initiated")
        case .restricted, .denied:
            return buildNativeTrackingStartResponse(started: false, reason: "permission_denied")
        case .authorizedAlways, .authorizedWhenInUse:
            if nativeTrackingUseSignificantChanges {
                manager.startMonitoringSignificantLocationChanges()
            } else {
                manager.startUpdatingLocation()
            }
            nativeTrackingRunning = true
            return buildNativeTrackingStartResponse(started: true, reason: "started")
        @unknown default:
            return buildNativeTrackingStartResponse(started: false, reason: "authorization_unknown")
        }
    }

    private func stopNativeTracking() {
        if nativeTrackingUseSignificantChanges {
            locationManager?.stopMonitoringSignificantLocationChanges()
        }
        locationManager?.stopUpdatingLocation()
        nativeLastPushAtMs = 0
        nativeTrackingRunning = false
    }

    private func nativeTrackingStatus() -> [String: Any] {
        return [
            "isRunning": nativeTrackingRunning,
            "id": nativeTrackingId as Any,
            "intervalMs": nativeTrackingIntervalMs,
            "minDistanceMeters": nativeTrackingDistance,
            "includeLocationMeta": nativeTrackingIncludeLocationMeta,
            "allowBackground": nativeTrackingAllowBackground,
            "useSignificantChanges": nativeTrackingUseSignificantChanges,
        ]
    }

    private func buildNativeTrackingStartResponse(started: Bool, reason: String) -> [String: Any] {
        return [
            "started": started,
            "reason": reason,
        ]
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard nativeTrackingRunning else {
            return
        }

        for location in locations {
            handleNativeLocationUpdate(location)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Native tracking location error: \(error.localizedDescription)")
    }

    private func handleNativeLocationUpdate(_ location: CLLocation) {
        guard let id = nativeTrackingId else {
            return
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        if nativeLastPushAtMs > 0 && (nowMs - nativeLastPushAtMs) < nativeTrackingIntervalMs {
            return
        }
        nativeLastPushAtMs = nowMs

        var data = nativeTrackingData
        if nativeTrackingIncludeLocationMeta {
            data["accuracy"] = location.horizontalAccuracy
            data["speed"] = location.speed
            data["heading"] = location.course
            data["altitude"] = location.altitude
            data["timestampMs"] = Int(location.timestamp.timeIntervalSince1970 * 1000)
        }

        let request = createWriteRequest(
            id: id,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            data: data
        )

        enqueuePendingWrite(request)
        writeLocationWithData(request) { isSuccess in
            if isSuccess, let requestId = request["requestId"] as? String {
                self.dequeuePendingWrite(requestId)
            }
        }
    }


   public func onListen(withArguments arguments: Any?,
                       eventSink: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = eventSink
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
      eventSink = nil
      return nil
    }




    private func sanitizeAdditionalData(_ metadata: [String: Any]) -> [AnyHashable: Any] {
        var sanitized: [AnyHashable: Any] = [:]

        for (key, value) in metadata {
            if key == "g" || key == "l" {
                continue
            }
            sanitized[key] = value
        }

        return sanitized
    }

    private func configurePersistenceIfNeeded() {
        if SwiftGeofirePlugin.persistenceConfigured {
            return
        }

        Database.database().isPersistenceEnabled = true
        SwiftGeofirePlugin.persistenceConfigured = true
    }

    private func loadPendingWrites() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: SwiftGeofirePlugin.pendingWritesKey) as? [[String: Any]] ?? []
    }

    private func savePendingWrites(_ writes: [[String: Any]]) {
        UserDefaults.standard.set(writes, forKey: SwiftGeofirePlugin.pendingWritesKey)
    }

    private func enqueuePendingWrite(_ request: [String: Any]) {
        var writes = loadPendingWrites()
        writes.append(request)
        savePendingWrites(writes)
    }

    private func dequeuePendingWrite(_ requestId: String) {
        let filtered = loadPendingWrites().filter { request in
            (request["requestId"] as? String) != requestId
        }
        savePendingWrites(filtered)
    }

    private func flushPendingWrites() {
        let writes = loadPendingWrites()
        for request in writes {
            writeLocationWithData(request) { isSuccess in
                if isSuccess, let requestId = request["requestId"] as? String {
                    self.dequeuePendingWrite(requestId)
                }
            }
        }
    }

    private func writeLocationWithData(_ request: [String: Any], completion: @escaping (Bool) -> Void) {
        guard
            let geoFire = geoFire,
            let ref = geoFireRef,
            let id = request["id"] as? String,
            let lat = request["lat"] as? Double,
            let lng = request["lng"] as? Double
        else {
            completion(false)
            return
        }

        let data = request["data"] as? [AnyHashable: Any] ?? [:]

        geoFire.setLocation(CLLocation(latitude: lat, longitude: lng), forKey: id) { error in
            if error != nil {
                completion(false)
                return
            }

            if data.isEmpty {
                completion(true)
                return
            }

            let payload: [AnyHashable: Any] = ["data": data]
            ref.child(id).updateChildValues(payload) { metadataError, _ in
                completion(metadataError == nil)
            }
        }
    }

    private func createWriteRequest(id: String, lat: Double, lng: Double, data: [AnyHashable: Any]) -> [String: Any] {
        return [
            "requestId": UUID().uuidString,
            "id": id,
            "lat": lat,
            "lng": lng,
            "data": data
        ]
    }

    private func emitQueryEventWithData(callBack: String, key: String, location: CLLocation, includeData: Bool) {
        guard let sink = eventSink else {
            circleQuery?.removeAllObservers()
            return
        }

        var payload: [String: Any] = [
            "callBack": callBack,
            "key": key,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]

        if !includeData {
            sink(payload)
            return
        }

        guard let ref = geoFireRef else {
            sink(payload)
            return
        }

        ref.child(key).observeSingleEvent(of: .value, with: { snapshot in
            if
                let value = snapshot.value as? [String: Any],
                let data = value["data"] as? [String: Any]
            {
                payload["data"] = data
            }
            sink(payload)
        }, withCancel: { _ in
            sink(payload)
        })
    }

}

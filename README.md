# flutter_geofire_plus

A Flutter plugin for realtime geospatial location updates and proximity queries.

This package supports:
1. Firebase Realtime Database + GeoFire native behavior (default)
2. Optional backend adapters for Firestore, Supabase, Postgres, and MySQL
3. Advanced filtering/ranking helpers for ride-dispatch workflows
4. Typed event/candidate APIs to avoid stringly-typed map usage
5. Optional native location tracking (Android/iOS), including background-oriented modes

## Installation

In pubspec.yaml:

```yaml
dependencies:
  flutter_geofire_plus: ^2.0.7
```

Then run:

```bash
flutter pub get
```

## iOS setup

Your app Podfile should include:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  pod 'GeoFire'

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

Add the following keys to your `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app uses your location to show nearby drivers.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app uses your location in the background to keep your position up to date.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

Notes:
1. Works with Swift and Objective-C host apps.
2. The plugin implementation is Swift with Objective-C bridge compatibility.
3. No custom GeoFire git fork is required.
4. Both `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription` are required for background tracking. Omitting either causes silent failures on iOS 13+.

## Android setup

No extra manual plugin registration is needed.

If you use native location tracking, add the required permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Required for background tracking (Android 10+) -->
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

<!-- Required when useForegroundService is true -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

You must also request `ACCESS_FINE_LOCATION` (and `ACCESS_BACKGROUND_LOCATION` for background) at runtime before calling `startNativeTracking`. The plugin does not request permissions automatically.

## Quickstart (Firebase default backend)

```dart
import 'package:flutter_geofire_plus/flutter_geofire_plus.dart';

Future<void> setup() async {
  final bool ok = await Geofire.initialize('drivers_live');
  if (!ok) {
    throw Exception('GeoFire initialize failed');
  }
}
```

Realtime Database rules must index g for your chosen path:

```json
{
  "rules": {
    ".read": true,
    ".write": true,
    "drivers_live": {
      ".indexOn": ["g"]
    }
  }
}
```

## Copy-Paste Templates

### Which template should I use?

| Scenario | Template | Key API |
|---|---|---|
| Driver app pushes lat/lng on each GPS tick from Dart | **A** | `Geofire.setLocation(...)` |
| Rider/passenger app queries and ranks nearby drivers | **B** | `Geofire.queryDriverCandidatesAtLocation(...)` |
| Driver app must track location in the background without Dart running | **C** | `Geofire.startNativeTrackingDetailed(...)` |
| You want Dart control but only need basic proximity events (no typed model) | **A** | `Geofire.queryAtLocation(...)` |
| You need custom score/rank logic beyond rating + priority | **B** | `Geofire.queryAtLocationAdvanced(...)` with `scoreBy:` |
| Android reliability matters most in background | **C** | set `useForegroundService: true` |
| iOS background with minimal battery use | **C** | set `useSignificantChanges: true` |

> Start with Template A + B for most apps. Add Template C only when Dart-side GPS is not reliable enough in background.

### Template A: Driver app publisher (Dart-driven updates)

```dart
import 'package:flutter_geofire_plus/flutter_geofire_plus.dart';

class DriverPublisher {
  static const String path = 'drivers_live';
  static const String driverId = 'driver_123';

  static Future<void> init() async {
    final bool ok = await Geofire.initialize(path);
    if (!ok) {
      throw Exception('GeoFire init failed');
    }
  }

  static Future<void> publish(double lat, double lng) async {
    await Geofire.setLocation(
      driverId,
      lat,
      lng,
      data: {
        'vehicleType': 'bike',
        'region': 'nairobi',
        'isVerified': true,
        'rating': 4.8,
        'activeTrips': 0,
        'priority': 2,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  static Future<void> remove() async {
    await Geofire.removeLocation(driverId);
  }
}
```

### Template B: Rider app consumer (ranked nearby candidates)

```dart
import 'dart:async';
import 'package:flutter_geofire_plus/flutter_geofire_plus.dart';

class RiderMatching {
  static const String path = 'drivers_live';
  StreamSubscription<List<GeofireDriverCandidate>>? _sub;

  Future<void> init() async {
    final bool ok = await Geofire.initialize(path);
    if (!ok) {
      throw Exception('GeoFire init failed');
    }
  }

  Future<void> start(double riderLat, double riderLng) async {
    await _sub?.cancel();
    _sub = Geofire.queryDriverCandidatesAtLocation(
      riderLat,
      riderLng,
      5,
      vehicleType: 'bike',
      region: 'nairobi',
      isVerified: true,
      minRating: 4.5,
      maxActiveTrips: 1,
      limit: 20,
    ).listen((candidates) {
      if (candidates.isEmpty) {
        return;
      }

      final best = candidates.first;
      print('Best: ${best.key}, score=${best.score}');
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    await Geofire.stopListener();
  }
}
```

### Template C: Native tracker mode (platform-driven updates)

```dart
import 'package:flutter_geofire_plus/flutter_geofire_plus.dart';

class NativeTracker {
  static const String path = 'drivers_live';
  static const String driverId = 'driver_123';

  static Future<void> init() async {
    final bool ok = await Geofire.initialize(path);
    if (!ok) {
      throw Exception('GeoFire init failed');
    }
  }

  static Future<void> start() async {
    final GeofireNativeTrackingStartResult result =
        await Geofire.startNativeTrackingDetailed(
      GeofireNativeTrackingConfig(
        id: driverId,
        intervalMs: 10000,
        minDistanceMeters: 20,
        includeLocationMeta: true,
        allowBackground: true,
        useForegroundService: true,
        useSignificantChanges: false,
        foregroundNotificationTitle: 'Driver online',
        foregroundNotificationBody: 'Sharing live location',
        data: {
          'vehicleType': 'bike',
          'region': 'nairobi',
          'isVerified': true,
        },
      ),
    );

    print('started=${result.started}, reason=${result.reason}');
  }

  static Future<void> status() async {
    final Map<String, dynamic> status = await Geofire.nativeTrackingStatus();
    print(status);
  }

  static Future<void> stop() async {
    await Geofire.stopNativeTracking();
  }
}
```

## Core APIs

### 1. Set location

```dart
final bool? ok = await Geofire.setLocation(
  'driver_123',
  -1.286389,
  36.817223,
  data: {
    'vehicleType': 'bike',
    'region': 'nairobi',
    'isVerified': true,
    'rating': 4.8,
    'activeTrips': 0,
    'priority': 2,
  },
);
```

Notes:
1. data supports arbitrary key/value pairs.
2. Keys g and l are reserved by GeoFire and ignored in custom data.
3. Writes are queued and retried when Firebase connectivity recovers.

### 2. Get location

```dart
final Map<String, dynamic> location = await Geofire.getLocation('driver_123');
print(location);
```

### 3. Remove location

```dart
await Geofire.removeLocation('driver_123');
```

### 4. Proximity query stream

```dart
final sub = Geofire.queryAtLocation(-1.286389, 36.817223, 5).listen((event) {
  final callback = event['callBack'];
  switch (callback) {
    case Geofire.onKeyEntered:
    case Geofire.onKeyMoved:
    case Geofire.onKeyExited:
    case Geofire.onGeoQueryReady:
      break;
  }
});
```

Stop query listeners:

```dart
await Geofire.stopListener();
await sub.cancel();
```

## Ride-dispatch helpers

### Filtered query

```dart
Geofire.queryAtLocationFiltered(
  -1.286389,
  36.817223,
  5,
  equalsData: {
    'vehicleType': 'bike',
    'region': 'nairobi',
    'isVerified': true,
  },
).listen((event) {
  print(event);
});
```

### Advanced filtering + ranking

```dart
Geofire.queryAtLocationAdvanced(
  -1.286389,
  36.817223,
  5,
  equalsData: {'region': 'nairobi'},
  minData: {'rating': 4.5},
  maxData: {'activeTrips': 1},
  limit: 20,
  scoreBy: (event) {
    final data = (event['data'] as Map?) ?? {};
    final rating = (data['rating'] as num?)?.toDouble() ?? 0;
    final priority = (data['priority'] as num?)?.toDouble() ?? 0;
    return (priority * 2.0) + rating;
  },
).listen((event) {
  print(event);
});
```

### Typed driver events

```dart
Geofire.queryDriversAtLocationTyped(
  -1.286389,
  36.817223,
  5,
  vehicleType: 'bike',
  region: 'nairobi',
  isVerified: true,
  minRating: 4.5,
  maxActiveTrips: 1,
).listen((event) {
  if (event.type == GeofireEventType.keyEntered ||
      event.type == GeofireEventType.keyMoved) {
    print(event.key);
    print(event.data.rating);
  }
});
```

### Ranked candidate stream (best for rider assignment)

```dart
Geofire.queryDriverCandidatesAtLocation(
  -1.286389,
  36.817223,
  5,
  vehicleType: 'bike',
  region: 'nairobi',
  isVerified: true,
  minRating: 4.5,
  maxActiveTrips: 1,
  limit: 20,
).listen((candidates) {
  if (candidates.isEmpty) return;
  final best = candidates.first;
  print(best.key);
  print(best.score);
});
```

## Native location tracking (optional)

Use native tracking when you want platform-side location collection instead of pushing every lat/lng from Dart.

### Start (simple bool)

```dart
final bool? started = await Geofire.startNativeTracking(
  GeofireNativeTrackingConfig(
    id: 'driver_123',
    intervalMs: 10000,
    minDistanceMeters: 20,
    includeLocationMeta: true,
    allowBackground: true,
    useForegroundService: true,   // Android option
    useSignificantChanges: false, // iOS option
    foregroundNotificationTitle: 'Driver online',
    foregroundNotificationBody: 'Sharing live location',
    data: {
      'vehicleType': 'bike',
      'region': 'nairobi',
    },
  ),
);
```

### Start (detailed reason codes)

```dart
final result = await Geofire.startNativeTrackingDetailed(
  GeofireNativeTrackingConfig(
    id: 'driver_123',
    allowBackground: true,
    useForegroundService: true,
  ),
);

print('started: ${result.started}, reason: ${result.reason}');
```

### Status and stop

```dart
final status = await Geofire.nativeTrackingStatus();
print(status);

await Geofire.stopNativeTracking();
```

Common reason codes include:
1. started
2. not_initialized
3. permission_denied
4. invalid_id
5. authorization_request_initiated (iOS)
6. foreground_service_start_failed (Android)

Background behavior notes:
1. Android reliability is strongest with foreground service mode enabled.
2. iOS background tracking requires proper Info.plist location usage keys and Background Modes.
3. Runtime permission prompts must be handled by your host app UX.

## Backend adapters (non-default backends)

By default, this package uses MethodChannelGeofireBackend (native Firebase behavior).

You can switch backend before initialize:

```dart
Geofire.configureBackend(
  SupabaseGeofireBackend(
    edgeFunctionBaseUrl: 'https://<project>.functions.supabase.co/geofire',
    anonKey: '<SUPABASE_ANON_KEY>',
  ),
);

await Geofire.initialize('drivers_live');
```

Built-in adapters:
1. MethodChannelGeofireBackend
2. FirestoreGeofireBackend
3. SupabaseGeofireBackend
4. PostgresGeofireBackend
5. MysqlGeofireBackend

Go starter backends:
1. backend_starters/postgres-go
2. backend_starters/mysql-go

### REST contract used by adapters

1. POST /initialize
2. POST /set-location
3. POST /remove-location
4. GET /get-location
5. GET /query

Expected /query row shape:

```json
[
  {
    "key": "driver_123",
    "latitude": -1.286389,
    "longitude": 36.817223,
    "data": {
      "vehicleType": "bike"
    }
  }
]
```

The package converts query rows into realtime-style callbacks:
1. onKeyEntered
2. onKeyMoved
3. onKeyExited
4. onGeoQueryReady

## Google Maps pattern (query by map center)

Use map camera center as query origin and restart on camera idle.

Best practices:
1. Re-query on onCameraIdle, not on every onCameraMove tick.
2. Cancel old stream before opening a new one.
3. Keep radius bounded for density.
4. Use data filters to reduce churn.

## Example app

A runnable dispatch demo is included in:
1. example/lib/main.dart
2. example/README.md

It demonstrates:
1. publish/remove driver location
2. ranked candidate stream
3. native tracking start/stop/status

## Troubleshooting

1. initialize returns false:
- Verify Firebase configuration and Realtime Database path.

2. Query returns no keys:
- Ensure rules include .indexOn: ["g"] for your path.

3. Native tracking start fails:
- Check runtime permissions, location services, and reason code from startNativeTrackingDetailed.

4. iOS background not updating:
- Verify Info.plist location usage strings and Background Modes capability.

5. Android background unstable:
- Enable useForegroundService and confirm notification/service permissions on device OS.

## On-Device AI Features

All AI features run entirely in Dart on the device. No external service, API key, or internet connection is required. They are fully opt-in and backward compatible — existing code is unaffected.

---

### GeofireKalmanFilter — GPS smoothing, velocity & ETA

Applies a Kalman filter to raw GPS readings per driver to remove noise, estimate speed, and predict future position or arrival time.

```dart
// One filter instance per driver.
final filters = <String, GeofireKalmanFilter>{};

Geofire.queryAtLocation(riderLat, riderLng, 5.0, includeData: true).listen((event) {
  final key  = event['key'] as String;
  final dLat = (event['latitude']  as num).toDouble();
  final dLng = (event['longitude'] as num).toDouble();

  final filter   = filters.putIfAbsent(key, () => GeofireKalmanFilter());
  final smoothed = filter.update(dLat, dLng);

  print('Speed : ${smoothed.speedKmh.toStringAsFixed(1)} km/h');

  // Where will the driver be in 30 seconds?
  final predicted = smoothed.predict(30);
  print('Predicted lat/lng: ${predicted.latitude}, ${predicted.longitude}');

  // ETA from driver position to rider
  final etaSeconds = filter.estimateEtaSeconds(dLat, dLng, riderLat, riderLng);
  if (etaSeconds != null) {
    print('ETA: ${(etaSeconds / 60).toStringAsFixed(1)} min');
  }
});
```

**Constructor parameters**

| Parameter | Default | Description |
|---|---|---|
| `processNoise` | `0.5` | How much the filter trusts new readings vs. the model. Higher = more responsive, noisier. |
| `measurementNoise` | `10.0` | Expected GPS horizontal error in metres. Higher = smoother, more lag. |

---

### GeofireVelocityGuard — GPS spoof & impossible-jump detection

Compares consecutive location readings per driver and flags any update that implies a physically impossible speed (e.g. GPS spoofing).

```dart
final guard = GeofireVelocityGuard(maxSpeedKmh: 180);

stream.listen((event) {
  final key  = event['key'] as String;
  final lat  = (event['latitude']  as num).toDouble();
  final lng  = (event['longitude'] as num).toDouble();

  final result = guard.check(key, lat, lng);

  if (result.isSuspicious) {
    // Discard or flag this update.
    print('Suspicious location for $key: ${result.reason}');
    // e.g. "Speed 8400.0 km/h exceeds limit of 180 km/h"
  } else {
    print('OK — speed: ${result.speedKmh.toStringAsFixed(1)} km/h');
    // trust the location update
  }
});

// Clear a driver's baseline when they go offline.
guard.remove(driverKey);
```

**Constructor parameters**

| Parameter | Default | Description |
|---|---|---|
| `maxSpeedKmh` | `200.0` | Maximum plausible speed. Cars: 180–220, motorcycles: 200, walking: 10. |

**`GeofireAnomalyResult` fields**

| Field | Type | Description |
|---|---|---|
| `key` | `String` | The driver key. |
| `isSuspicious` | `bool` | `true` when the jump exceeds `maxSpeedKmh`. |
| `speedKmh` | `double` | Computed speed between the last two readings. |
| `reason` | `String?` | Human-readable description when `isSuspicious` is `true`. |

---

### GeoFireSpatialCluster — deduplicate bunched drivers

Groups a list of `GeofireDriverCandidate`s into spatial clusters so that several drivers parked in the same block appear as a single entry. The best-scored driver in each cluster is surfaced as the representative.

```dart
// Get candidates from queryDriverCandidatesAtLocation.
Geofire.queryDriverCandidatesAtLocation(riderLat, riderLng, 5.0).listen((candidates) {

  final clusters = GeoFireSpatialCluster.cluster(
    candidates,
    clusterRadiusKm: 0.5, // drivers within 500 m of the seed are grouped
  );

  for (final cluster in clusters) {
    print('Cluster of ${cluster.size} driver(s) near '
        '${cluster.centroidLat.toStringAsFixed(5)}, '
        '${cluster.centroidLng.toStringAsFixed(5)}');
    print('Best driver: ${cluster.bestCandidate.key} '
        '(score: ${cluster.bestCandidate.score.toStringAsFixed(2)})');
  }

  // Show only one driver per cluster on the map.
  final topDrivers = clusters.map((c) => c.bestCandidate).toList();
});
```

**`cluster()` parameters**

| Parameter | Default | Description |
|---|---|---|
| `clusterRadiusKm` | `0.5` | Drivers within this radius of the seed are merged into one cluster. |

**`GeofireCluster` fields**

| Field | Type | Description |
|---|---|---|
| `centroidLat/Lng` | `double` | Average position of all members. |
| `candidates` | `List<GeofireDriverCandidate>` | Every driver in the cluster. |
| `bestCandidate` | `GeofireDriverCandidate` | Highest-score member — use this as the map pin. |
| `size` | `int` | Number of drivers grouped. |

---

### Combining all three

```dart
final filters = <String, GeofireKalmanFilter>{};
final guard   = GeofireVelocityGuard(maxSpeedKmh: 180);

Geofire.queryDriverCandidatesAtLocation(riderLat, riderLng, 5.0).listen((candidates) {
  final trusted = <GeofireDriverCandidate>[];

  for (final c in candidates) {
    // 1. Spoof check
    final anomaly = guard.check(c.key, c.latitude, c.longitude);
    if (anomaly.isSuspicious) continue;

    // 2. Smooth + get ETA
    final filter   = filters.putIfAbsent(c.key, () => GeofireKalmanFilter());
    final smoothed = filter.update(c.latitude, c.longitude);
    final eta      = filter.estimateEtaSeconds(
        c.latitude, c.longitude, riderLat, riderLng);

    print('${c.key}: ${smoothed.speedKmh.toStringAsFixed(1)} km/h, '
        'ETA ${eta != null ? (eta / 60).toStringAsFixed(1) : "?"} min');

    trusted.add(c);
  }

  // 3. Cluster remaining candidates
  final clusters  = GeoFireSpatialCluster.cluster(trusted);
  final topDrivers = clusters.map((cl) => cl.bestCandidate).toList();
  // Render topDrivers on map.
});
```

## Contributing

Pull requests and issue reports are welcome.

# flutter_geofire_plus example

This example demonstrates a realistic driver/rider flow for ride dispatch:

1. Driver app behavior: publish live location with metadata using `setLocation(..., data: ...)`
2. Rider app behavior: consume ranked candidates using `queryDriverCandidatesAtLocation(...)`
3. Native app behavior: start/stop native location tracking and inspect detailed start reasons

This demo uses the default backend. If you want Firestore/Supabase/Postgres/MySQL,
configure a backend adapter in app startup using `Geofire.configureBackend(...)`.

## Run the example

1. Configure Firebase in this example app (`google-services.json` / iOS setup).
2. Ensure your Realtime Database rules include `.indexOn: ["g"]` for the reference path.
3. Run:

```
flutter pub get
flutter run
```

## What to test in the UI

1. Tap `Publish Driver` to write demo driver location + metadata.
2. Observe `Best Candidate` and the `Candidate List` update in real time.
3. Tap `Remove Driver` and watch candidate updates.
4. Tap `Restart Query` to re-subscribe the rider query stream.
5. Tap `Start Native Tracking` to test native start flow and reason codes.
6. Tap `Native Status` to inspect current native tracking runtime status.
7. Tap `Stop Native Tracking` to stop native location updates.

## Native tracking notes

1. If native start fails, check the reported reason shown in the app status.
2. Common reasons: missing runtime permission, tracking called before `initialize`, disabled device location services.
3. For Android background reliability, foreground service mode is enabled in this demo config.
4. For iOS background behavior, ensure location usage descriptions and Background Modes are configured in your host app.

## Querying another region (not user location)

For rider maps, use the map camera center as query origin and restart query on camera idle.
See the package README section: `Query from any location/region and render on Google Maps`.

The implementation is in `example/lib/main.dart`.


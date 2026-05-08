import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef GeofireScoreBuilder = double Function(Map<String, dynamic> event);
typedef GeofireDriverScoreBuilder = double Function(
    Map<String, dynamic> event, Map<dynamic, dynamic> data);

enum GeofireEventType {
  keyEntered,
  keyMoved,
  keyExited,
  geoQueryReady,
  unknown,
}

class GeofireDriverData {
  GeofireDriverData(this.values);

  final Map<String, dynamic> values;

  T? get<T>(String key) {
    final Object? value = values[key];
    if (value is T) {
      return value;
    }
    return null;
  }

  String? get vehicleType => get<String>('vehicleType');
  String? get region => get<String>('region');
  bool? get isVerified => get<bool>('isVerified');
  double? get rating => _asDouble(values['rating']);
  int? get activeTrips => _asInt(values['activeTrips']);
  double? get priority => _asDouble(values['priority']);

  static double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}

class GeofireDriverEvent {
  GeofireDriverEvent({
    required this.type,
    required this.key,
    this.latitude,
    this.longitude,
    required this.data,
    required this.raw,
    this.filteredResult,
    this.rankedResult,
  });

  final GeofireEventType type;
  final String key;
  final double? latitude;
  final double? longitude;
  final GeofireDriverData data;
  final Map<String, dynamic> raw;
  final List<String>? filteredResult;
  final List<String>? rankedResult;

  factory GeofireDriverEvent.fromMap(Map<String, dynamic> map) {
    final Object? rawData = map['data'];
    final Map<String, dynamic> dataMap = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    return GeofireDriverEvent(
      type: _eventTypeFromCallback((map['callBack'] ?? '').toString()),
      key: (map['key'] ?? '').toString(),
      latitude: _asDouble(map['latitude']),
      longitude: _asDouble(map['longitude']),
      data: GeofireDriverData(dataMap),
      raw: map,
      filteredResult: _asStringList(map['filteredResult']),
      rankedResult: _asStringList(map['rankedResult']),
    );
  }

  static GeofireEventType _eventTypeFromCallback(String callback) {
    switch (callback) {
      case Geofire.onKeyEntered:
        return GeofireEventType.keyEntered;
      case Geofire.onKeyMoved:
        return GeofireEventType.keyMoved;
      case Geofire.onKeyExited:
        return GeofireEventType.keyExited;
      case Geofire.onGeoQueryReady:
        return GeofireEventType.geoQueryReady;
      default:
        return GeofireEventType.unknown;
    }
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static List<String>? _asStringList(Object? value) {
    if (value is List) {
      return value.map((Object? e) => (e ?? '').toString()).toList();
    }
    return null;
  }
}

class GeofireDriverCandidate {
  GeofireDriverCandidate({
    required this.key,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.score,
    required this.data,
    required this.sourceEvent,
  });

  final String key;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final double score;
  final GeofireDriverData data;
  final GeofireDriverEvent sourceEvent;
}

abstract class GeofireBackend {
  Future<bool> initialize(String path);

  Future<bool?> setLocation(String id, double latitude, double longitude,
      {Map<String, dynamic>? data});

  Future<bool?> removeLocation(String id);

  Future<Map<String, dynamic>> getLocation(String id);

  Stream<dynamic> queryAtLocation(double lat, double lng, double radius,
      {bool includeData = false});

  Future<bool?> stopListener();

  Future<bool?> startNativeTracking(Map<String, dynamic> config);

  Future<Map<String, dynamic>> startNativeTrackingDetailed(
      Map<String, dynamic> config);

  Future<bool?> stopNativeTracking();

  Future<Map<String, dynamic>> nativeTrackingStatus();
}

class MethodChannelGeofireBackend implements GeofireBackend {
  MethodChannelGeofireBackend({
    MethodChannel? channel,
    EventChannel? stream,
  })  : _channel = channel ?? const MethodChannel('geofire'),
        _stream = stream ?? const EventChannel('geofireStream');

  final MethodChannel _channel;
  final EventChannel _stream;

  Stream<dynamic>? _queryAtLocation;

  @override
  Future<bool> initialize(String path) async {
    final dynamic r = await _channel
        .invokeMethod('GeoFire.start', <String, dynamic>{'path': path});
    return r ?? false;
  }

  @override
  Future<bool?> setLocation(String id, double latitude, double longitude,
      {Map<String, dynamic>? data}) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'id': id,
      'lat': latitude,
      'lng': longitude,
    };

    if (data != null && data.isNotEmpty) {
      payload['data'] = data;
    }

    final bool? isSet = await _channel.invokeMethod(
        data != null && data.isNotEmpty ? 'setLocationWithData' : 'setLocation',
        payload);
    return isSet;
  }

  @override
  Future<bool?> removeLocation(String id) async {
    return _channel.invokeMethod('removeLocation', <String, dynamic>{'id': id});
  }

  @override
  Future<Map<String, dynamic>> getLocation(String id) async {
    final Map<dynamic, dynamic> response = await (_channel
        .invokeMethod('getLocation', <String, dynamic>{'id': id}));

    final Map<String, dynamic> location = <String, dynamic>{};
    response.forEach((dynamic key, dynamic value) {
      location[key.toString()] = value;
    });

    return location;
  }

  @override
  Stream<dynamic> queryAtLocation(double lat, double lng, double radius,
      {bool includeData = false}) {
    _channel.invokeMethod('queryAtLocation', <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'radius': radius,
      'includeData': includeData,
    }).then((dynamic _) {
      // no-op
    }).catchError((dynamic _) {
      // no-op
    });

    _queryAtLocation ??= _stream.receiveBroadcastStream();
    return _queryAtLocation!;
  }

  @override
  Future<bool?> stopListener() async {
    return _channel.invokeMethod('stopListener', <String, dynamic>{});
  }

  @override
  Future<bool?> startNativeTracking(Map<String, dynamic> config) async {
    return _channel.invokeMethod('startNativeTracking', config);
  }

  @override
  Future<Map<String, dynamic>> startNativeTrackingDetailed(
      Map<String, dynamic> config) async {
    final Map<dynamic, dynamic>? response =
        await _channel.invokeMethod('startNativeTrackingDetailed', config);
    if (response == null) {
      return <String, dynamic>{
        'started': false,
        'reason': 'unknown',
      };
    }
    return response.map((dynamic key, dynamic value) =>
        MapEntry<String, dynamic>(key.toString(), value));
  }

  @override
  Future<bool?> stopNativeTracking() async {
    return _channel.invokeMethod('stopNativeTracking', <String, dynamic>{});
  }

  @override
  Future<Map<String, dynamic>> nativeTrackingStatus() async {
    final Map<dynamic, dynamic>? response =
        await _channel.invokeMethod('nativeTrackingStatus');
    if (response == null) {
      return <String, dynamic>{};
    }
    return response.map((dynamic key, dynamic value) =>
        MapEntry<String, dynamic>(key.toString(), value));
  }
}

class RestGeofireBackend implements GeofireBackend {
  RestGeofireBackend({
    required this.baseUrl,
    this.headers = const <String, String>{},
    this.pollInterval = const Duration(seconds: 2),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Map<String, String> headers;
  final Duration pollInterval;
  final http.Client _client;

  String? _path;
  StreamController<dynamic>? _controller;
  Timer? _pollTimer;

  double? _queryLat;
  double? _queryLng;
  double? _queryRadius;
  bool _includeData = false;

  bool _hasSentReady = false;
  Map<String, Map<String, dynamic>> _lastResultsByKey =
      <String, Map<String, dynamic>>{};

  @override
  Future<bool> initialize(String path) async {
    _path = path;

    final Uri uri = _uri('/initialize');
    final http.Response response = await _client.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(<String, dynamic>{'path': path}),
    );

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  @override
  Future<bool?> setLocation(String id, double latitude, double longitude,
      {Map<String, dynamic>? data}) async {
    final Uri uri = _uri('/set-location');
    final http.Response response = await _client.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(<String, dynamic>{
        'path': _path,
        'id': id,
        'lat': latitude,
        'lng': longitude,
        'data': data ?? <String, dynamic>{},
      }),
    );

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  @override
  Future<bool?> removeLocation(String id) async {
    final Uri uri = _uri('/remove-location');
    final http.Response response = await _client.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(<String, dynamic>{'path': _path, 'id': id}),
    );

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  @override
  Future<Map<String, dynamic>> getLocation(String id) async {
    final Uri uri = _uri('/get-location').replace(
      queryParameters: <String, String>{
        'path': _path ?? '',
        'id': id,
      },
    );

    final http.Response response = await _client.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return <String, dynamic>{'error': 'Request failed'};
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return <String, dynamic>{'error': 'Invalid response'};
  }

  @override
  Stream<dynamic> queryAtLocation(double lat, double lng, double radius,
      {bool includeData = false}) {
    _queryLat = lat;
    _queryLng = lng;
    _queryRadius = radius;
    _includeData = includeData;

    _controller ??= StreamController<dynamic>.broadcast(
      onCancel: () {
        if (!(_controller?.hasListener ?? false)) {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
      },
    );

    _lastResultsByKey = <String, Map<String, dynamic>>{};
    _hasSentReady = false;

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      _pollQuery();
    });
    _pollQuery();

    return _controller!.stream;
  }

  @override
  Future<bool?> stopListener() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _controller?.add(<String, dynamic>{
      'callBack': Geofire.onGeoQueryReady,
      'result': <String>[],
    });
    return true;
  }

  @override
  Future<bool?> startNativeTracking(Map<String, dynamic> config) async {
    return false;
  }

  @override
  Future<Map<String, dynamic>> startNativeTrackingDetailed(
      Map<String, dynamic> config) async {
    return <String, dynamic>{
      'started': false,
      'reason': 'unsupported_backend',
    };
  }

  @override
  Future<bool?> stopNativeTracking() async {
    return false;
  }

  @override
  Future<Map<String, dynamic>> nativeTrackingStatus() async {
    return <String, dynamic>{
      'isRunning': false,
      'error': 'Native tracking is only available on MethodChannel backend',
    };
  }

  Future<void> _pollQuery() async {
    if (_controller == null ||
        _queryLat == null ||
        _queryLng == null ||
        _queryRadius == null) {
      return;
    }

    final Uri uri = _uri('/query').replace(
      queryParameters: <String, String>{
        'path': _path ?? '',
        'lat': _queryLat.toString(),
        'lng': _queryLng.toString(),
        'radius': _queryRadius.toString(),
        'includeData': _includeData.toString(),
      },
    );

    final http.Response response = await _client.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return;
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return;
    }

    final List<dynamic> rows = decoded;
    final Map<String, Map<String, dynamic>> currentByKey =
        <String, Map<String, dynamic>>{};

    for (final dynamic row in rows) {
      if (row is! Map) {
        continue;
      }

      final Map<String, dynamic> value = Map<String, dynamic>.from(row);
      final String key = (value['key'] ?? '').toString();
      if (key.isEmpty) {
        continue;
      }
      currentByKey[key] = value;
    }

    for (final MapEntry<String, Map<String, dynamic>> entry
        in currentByKey.entries) {
      final String key = entry.key;
      final Map<String, dynamic> current = entry.value;
      final Map<String, dynamic>? previous = _lastResultsByKey[key];

      final Map<String, dynamic> payload = <String, dynamic>{
        'key': key,
        'latitude': _asDouble(current['latitude'] ?? current['lat']),
        'longitude': _asDouble(current['longitude'] ?? current['lng']),
      };

      if (_includeData && current['data'] is Map) {
        payload['data'] = current['data'];
      }

      if (previous == null) {
        payload['callBack'] = Geofire.onKeyEntered;
        _controller?.add(payload);
      } else {
        final double? prevLat =
            _asDouble(previous['latitude'] ?? previous['lat']);
        final double? prevLng =
            _asDouble(previous['longitude'] ?? previous['lng']);
        final double? curLat = _asDouble(payload['latitude']);
        final double? curLng = _asDouble(payload['longitude']);

        if (prevLat != curLat || prevLng != curLng) {
          payload['callBack'] = Geofire.onKeyMoved;
          _controller?.add(payload);
        }
      }
    }

    for (final String previousKey in _lastResultsByKey.keys) {
      if (!currentByKey.containsKey(previousKey)) {
        _controller?.add(<String, dynamic>{
          'callBack': Geofire.onKeyExited,
          'key': previousKey,
        });
      }
    }

    if (!_hasSentReady) {
      _hasSentReady = true;
      _controller?.add(<String, dynamic>{
        'callBack': Geofire.onGeoQueryReady,
        'result': currentByKey.keys.toList(),
      });
    }

    _lastResultsByKey = currentByKey;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _jsonHeaders => <String, String>{
        ...headers,
        'content-type': 'application/json',
      };

  static double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

class FirestoreGeofireBackend extends RestGeofireBackend {
  FirestoreGeofireBackend({
    required String functionBaseUrl,
    Map<String, String> headers = const <String, String>{},
    Duration pollInterval = const Duration(seconds: 2),
  }) : super(
          baseUrl: functionBaseUrl,
          headers: headers,
          pollInterval: pollInterval,
        );
}

class SupabaseGeofireBackend extends RestGeofireBackend {
  SupabaseGeofireBackend({
    required String edgeFunctionBaseUrl,
    required String anonKey,
    Duration pollInterval = const Duration(seconds: 2),
  }) : super(
          baseUrl: edgeFunctionBaseUrl,
          headers: <String, String>{
            'apikey': anonKey,
            'authorization': 'Bearer $anonKey',
          },
          pollInterval: pollInterval,
        );
}

class PostgresGeofireBackend extends RestGeofireBackend {
  PostgresGeofireBackend({
    required String apiBaseUrl,
    Map<String, String> headers = const <String, String>{},
    Duration pollInterval = const Duration(seconds: 2),
  }) : super(
          baseUrl: apiBaseUrl,
          headers: headers,
          pollInterval: pollInterval,
        );
}

class MysqlGeofireBackend extends RestGeofireBackend {
  MysqlGeofireBackend({
    required String apiBaseUrl,
    Map<String, String> headers = const <String, String>{},
    Duration pollInterval = const Duration(seconds: 2),
  }) : super(
          baseUrl: apiBaseUrl,
          headers: headers,
          pollInterval: pollInterval,
        );
}

class GeofireNativeTrackingConfig {
  GeofireNativeTrackingConfig({
    required this.id,
    this.intervalMs = 10000,
    this.minDistanceMeters = 20,
    this.includeLocationMeta = true,
    this.allowBackground = false,
    this.useForegroundService = false,
    this.useSignificantChanges = false,
    this.foregroundNotificationTitle,
    this.foregroundNotificationBody,
    this.foregroundNotificationChannelId,
    this.foregroundNotificationChannelName,
    this.foregroundNotificationId,
    this.data,
  });

  final String id;
  final int intervalMs;
  final double minDistanceMeters;
  final bool includeLocationMeta;
  final bool allowBackground;
  final bool useForegroundService;
  final bool useSignificantChanges;
  final String? foregroundNotificationTitle;
  final String? foregroundNotificationBody;
  final String? foregroundNotificationChannelId;
  final String? foregroundNotificationChannelName;
  final int? foregroundNotificationId;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'intervalMs': intervalMs,
      'minDistanceMeters': minDistanceMeters,
      'includeLocationMeta': includeLocationMeta,
      'allowBackground': allowBackground,
      'useForegroundService': useForegroundService,
      'useSignificantChanges': useSignificantChanges,
      if (foregroundNotificationTitle != null)
        'foregroundNotificationTitle': foregroundNotificationTitle,
      if (foregroundNotificationBody != null)
        'foregroundNotificationBody': foregroundNotificationBody,
      if (foregroundNotificationChannelId != null)
        'foregroundNotificationChannelId': foregroundNotificationChannelId,
      if (foregroundNotificationChannelName != null)
        'foregroundNotificationChannelName': foregroundNotificationChannelName,
      if (foregroundNotificationId != null)
        'foregroundNotificationId': foregroundNotificationId,
      if (data != null && data!.isNotEmpty) 'data': data,
    };
  }
}

class GeofireNativeTrackingStartResult {
  GeofireNativeTrackingStartResult({
    required this.started,
    required this.reason,
    this.details,
  });

  final bool started;
  final String reason;
  final Map<String, dynamic>? details;

  factory GeofireNativeTrackingStartResult.fromMap(Map<String, dynamic> map) {
    return GeofireNativeTrackingStartResult(
      started: map['started'] == true,
      reason: (map['reason'] ?? 'unknown').toString(),
      details: map['details'] is Map
          ? Map<String, dynamic>.from(map['details'] as Map)
          : null,
    );
  }
}

class Geofire {
  static const onKeyEntered = 'onKeyEntered';
  static const onGeoQueryReady = 'onGeoQueryReady';
  static const onKeyMoved = 'onKeyMoved';
  static const onKeyExited = 'onKeyExited';

  static GeofireBackend _backend = MethodChannelGeofireBackend();

  static void configureBackend(GeofireBackend backend) {
    _backend = backend;
  }

  static void useDefaultBackend() {
    _backend = MethodChannelGeofireBackend();
  }

  static Future<bool> initialize(String path) {
    return _backend.initialize(path);
  }

  static Future<bool?> setLocation(String id, double latitude, double longitude,
      {Map<String, dynamic>? data}) {
    return _backend.setLocation(id, latitude, longitude, data: data);
  }

  static Future<bool?> removeLocation(String id) {
    return _backend.removeLocation(id);
  }

  static Future<bool?> stopListener() {
    return _backend.stopListener();
  }

  static Future<bool?> startNativeTracking(GeofireNativeTrackingConfig config) {
    return _backend.startNativeTracking(config.toMap());
  }

  static Future<GeofireNativeTrackingStartResult> startNativeTrackingDetailed(
      GeofireNativeTrackingConfig config) async {
    final Map<String, dynamic> response =
        await _backend.startNativeTrackingDetailed(config.toMap());
    return GeofireNativeTrackingStartResult.fromMap(response);
  }

  static Future<bool?> stopNativeTracking() {
    return _backend.stopNativeTracking();
  }

  static Future<Map<String, dynamic>> nativeTrackingStatus() {
    return _backend.nativeTrackingStatus();
  }

  static Future<Map<String, dynamic>> getLocation(String id) {
    return _backend.getLocation(id);
  }

  static Stream<dynamic> queryAtLocation(double lat, double lng, double radius,
      {bool includeData = false}) {
    return _backend.queryAtLocation(lat, lng, radius, includeData: includeData);
  }

  static Stream<Map<String, dynamic>> queryAtLocationFiltered(
      double lat, double lng, double radius,
      {Map<String, dynamic>? equalsData}) {
    return queryAtLocationAdvanced(
      lat,
      lng,
      radius,
      equalsData: equalsData,
    );
  }

  static Stream<Map<String, dynamic>> queryAtLocationAdvanced(
      double lat, double lng, double radius,
      {Map<String, dynamic>? equalsData,
      Map<String, num>? minData,
      Map<String, num>? maxData,
      GeofireScoreBuilder? scoreBy,
      int? limit}) async* {
    final Stream<dynamic> source = queryAtLocation(lat, lng, radius,
        includeData: _requiresData(
            equalsData: equalsData, minData: minData, maxData: maxData));

    final Set<String> matchedKeys = <String>{};
    final Map<String, double> scoreByKey = <String, double>{};

    await for (final dynamic event in source) {
      if (event is! Map) {
        continue;
      }

      final Map<String, dynamic> map = Map<String, dynamic>.from(event);
      final String callBack = (map['callBack'] ?? '').toString();
      final String key = (map['key'] ?? '').toString();

      if (callBack == onGeoQueryReady) {
        map['filteredResult'] = matchedKeys.toList();
        if (scoreBy != null) {
          map['rankedResult'] = _rankedKeys(scoreByKey, limit: limit);
        }
        yield map;
        continue;
      }

      if (callBack == onKeyExited) {
        scoreByKey.remove(key);
        if (key.isNotEmpty && matchedKeys.remove(key)) {
          yield map;
        }
        continue;
      }

      if (callBack != onKeyEntered && callBack != onKeyMoved) {
        yield map;
        continue;
      }

      if (_matchesDataFilter(map['data'], equalsData,
          minData: minData, maxData: maxData)) {
        if (key.isNotEmpty) {
          matchedKeys.add(key);
          if (scoreBy != null) {
            scoreByKey[key] = scoreBy(map);
          }
        }

        if (scoreBy == null ||
            _isWithinTopLimit(key, scoreByKey, limit: limit)) {
          yield map;
        }
      } else {
        if (key.isNotEmpty) {
          matchedKeys.remove(key);
          scoreByKey.remove(key);
        }
      }
    }
  }

  static Stream<Map<String, dynamic>> queryDriversAtLocation(
      double riderLat, double riderLng, double radius,
      {String? vehicleType,
      String? region,
      bool? isVerified,
      Map<String, dynamic>? equalsData,
      double? minRating,
      int? maxActiveTrips,
      Map<String, num>? minData,
      Map<String, num>? maxData,
      int? limit,
      GeofireDriverScoreBuilder? scoreBy}) {
    final Map<String, dynamic> matchEqualsData = <String, dynamic>{};
    if (equalsData != null && equalsData.isNotEmpty) {
      matchEqualsData.addAll(equalsData);
    }
    if (vehicleType != null && vehicleType.isNotEmpty) {
      matchEqualsData['vehicleType'] = vehicleType;
    }
    if (region != null && region.isNotEmpty) {
      matchEqualsData['region'] = region;
    }
    if (isVerified != null) {
      matchEqualsData['isVerified'] = isVerified;
    }

    final Map<String, num> matchMinData = <String, num>{};
    if (minData != null && minData.isNotEmpty) {
      matchMinData.addAll(minData);
    }
    if (minRating != null) {
      matchMinData['rating'] = minRating;
    }

    final Map<String, num> matchMaxData = <String, num>{};
    if (maxData != null && maxData.isNotEmpty) {
      matchMaxData.addAll(maxData);
    }
    if (maxActiveTrips != null) {
      matchMaxData['activeTrips'] = maxActiveTrips;
    }

    return queryAtLocationAdvanced(
      riderLat,
      riderLng,
      radius,
      equalsData: matchEqualsData.isEmpty ? null : matchEqualsData,
      minData: matchMinData.isEmpty ? null : matchMinData,
      maxData: matchMaxData.isEmpty ? null : matchMaxData,
      limit: limit,
      scoreBy: (Map<String, dynamic> event) {
        final Object? rawData = event['data'];
        final Map<dynamic, dynamic> data =
            rawData is Map ? rawData : <dynamic, dynamic>{};

        if (scoreBy != null) {
          return scoreBy(event, data);
        }

        final double distanceKm = _distanceKm(
          riderLat,
          riderLng,
          (event['latitude'] as num?)?.toDouble() ?? riderLat,
          (event['longitude'] as num?)?.toDouble() ?? riderLng,
        );

        return _defaultDispatchScore(
          distanceKm,
          (data['rating'] as num?)?.toDouble() ?? 0.0,
          (data['priority'] as num?)?.toDouble() ?? 0.0,
          (data['activeTrips'] as num?)?.toDouble() ?? 0.0,
        );
      },
    );
  }

  static Stream<GeofireDriverEvent> queryDriversAtLocationTyped(
      double riderLat, double riderLng, double radius,
      {String? vehicleType,
      String? region,
      bool? isVerified,
      Map<String, dynamic>? equalsData,
      double? minRating,
      int? maxActiveTrips,
      Map<String, num>? minData,
      Map<String, num>? maxData,
      int? limit,
      GeofireDriverScoreBuilder? scoreBy}) {
    return queryDriversAtLocation(
      riderLat,
      riderLng,
      radius,
      vehicleType: vehicleType,
      region: region,
      isVerified: isVerified,
      equalsData: equalsData,
      minRating: minRating,
      maxActiveTrips: maxActiveTrips,
      minData: minData,
      maxData: maxData,
      limit: limit,
      scoreBy: scoreBy,
    ).map((Map<String, dynamic> event) => GeofireDriverEvent.fromMap(event));
  }

  static Stream<List<GeofireDriverCandidate>> queryDriverCandidatesAtLocation(
      double riderLat, double riderLng, double radius,
      {String? vehicleType,
      String? region,
      bool? isVerified,
      Map<String, dynamic>? equalsData,
      double? minRating,
      int? maxActiveTrips,
      Map<String, num>? minData,
      Map<String, num>? maxData,
      int limit = 20,
      GeofireDriverScoreBuilder? scoreBy}) async* {
    final Map<String, GeofireDriverCandidate> candidatesByKey =
        <String, GeofireDriverCandidate>{};

    await for (final GeofireDriverEvent event in queryDriversAtLocationTyped(
      riderLat,
      riderLng,
      radius,
      vehicleType: vehicleType,
      region: region,
      isVerified: isVerified,
      equalsData: equalsData,
      minRating: minRating,
      maxActiveTrips: maxActiveTrips,
      minData: minData,
      maxData: maxData,
      limit: null,
      scoreBy: scoreBy,
    )) {
      if (event.type == GeofireEventType.keyExited) {
        candidatesByKey.remove(event.key);
      } else if (event.type == GeofireEventType.keyEntered ||
          event.type == GeofireEventType.keyMoved) {
        if (event.latitude != null && event.longitude != null) {
          final double distanceKm = _distanceKm(
            riderLat,
            riderLng,
            event.latitude!,
            event.longitude!,
          );
          final double score = _computeDispatchScore(
            riderLat,
            riderLng,
            event,
            scoreBy: scoreBy,
          );

          candidatesByKey[event.key] = GeofireDriverCandidate(
            key: event.key,
            latitude: event.latitude!,
            longitude: event.longitude!,
            distanceKm: distanceKm,
            score: score,
            data: event.data,
            sourceEvent: event,
          );
        }
      }

      final List<GeofireDriverCandidate> ranked = candidatesByKey.values
          .toList()
        ..sort((GeofireDriverCandidate a, GeofireDriverCandidate b) =>
            b.score.compareTo(a.score));

      if (limit > 0 && ranked.length > limit) {
        yield ranked.take(limit).toList();
      } else {
        yield ranked;
      }
    }
  }

  static bool _requiresData(
      {Map<String, dynamic>? equalsData,
      Map<String, num>? minData,
      Map<String, num>? maxData}) {
    return (equalsData != null && equalsData.isNotEmpty) ||
        (minData != null && minData.isNotEmpty) ||
        (maxData != null && maxData.isNotEmpty);
  }

  static bool _matchesDataFilter(
      dynamic rawData, Map<String, dynamic>? equalsData,
      {Map<String, num>? minData, Map<String, num>? maxData}) {
    final bool hasEqualsData = equalsData != null && equalsData.isNotEmpty;
    final bool hasMinData = minData != null && minData.isNotEmpty;
    final bool hasMaxData = maxData != null && maxData.isNotEmpty;

    if (!hasEqualsData && !hasMinData && !hasMaxData) {
      return true;
    }

    if (rawData is! Map) {
      return false;
    }

    final Map<dynamic, dynamic> data = rawData;
    if (hasEqualsData) {
      for (final MapEntry<String, dynamic> entry in equalsData.entries) {
        if (!data.containsKey(entry.key) || data[entry.key] != entry.value) {
          return false;
        }
      }
    }

    if (hasMinData) {
      for (final MapEntry<String, num> entry in minData.entries) {
        final Object? current = data[entry.key];
        if (current is! num || current < entry.value) {
          return false;
        }
      }
    }

    if (hasMaxData) {
      for (final MapEntry<String, num> entry in maxData.entries) {
        final Object? current = data[entry.key];
        if (current is! num || current > entry.value) {
          return false;
        }
      }
    }

    return true;
  }

  static List<String> _rankedKeys(Map<String, double> scoreByKey,
      {int? limit}) {
    final List<MapEntry<String, double>> entries = scoreByKey.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));

    if (limit == null || limit <= 0 || limit >= entries.length) {
      return entries.map((MapEntry<String, double> e) => e.key).toList();
    }

    return entries
        .take(limit)
        .map((MapEntry<String, double> e) => e.key)
        .toList();
  }

  static bool _isWithinTopLimit(String key, Map<String, double> scoreByKey,
      {int? limit}) {
    if (limit == null || limit <= 0) {
      return true;
    }

    final List<String> topKeys = _rankedKeys(scoreByKey, limit: limit);
    return topKeys.contains(key);
  }

  static double _distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLng = _toRadians(lng2 - lng1);
    final double lat1Rad = _toRadians(lat1);
    final double lat2Rad = _toRadians(lat2);

    final double sinLat = math.sin(dLat / 2);
    final double sinLng = math.sin(dLng / 2);
    final double a = sinLat * sinLat +
        math.cos(lat1Rad) * math.cos(lat2Rad) * sinLng * sinLng;
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _computeDispatchScore(
      double riderLat, double riderLng, GeofireDriverEvent event,
      {GeofireDriverScoreBuilder? scoreBy}) {
    if (scoreBy != null) {
      return scoreBy(event.raw, event.data.values);
    }

    final double latitude = event.latitude ?? riderLat;
    final double longitude = event.longitude ?? riderLng;
    final double distanceKm =
        _distanceKm(riderLat, riderLng, latitude, longitude);

    return _defaultDispatchScore(
      distanceKm,
      event.data.rating ?? 0.0,
      event.data.priority ?? 0.0,
      (event.data.activeTrips ?? 0).toDouble(),
    );
  }

  static double _defaultDispatchScore(
      double distanceKm, double rating, double priority, double activeTrips) {
    return (priority * 2.0) + rating - (distanceKm * 1.5) - activeTrips;
  }

  static double _toRadians(double degree) => degree * 0.017453292519943295;
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared private helper — Haversine distance used by all AI features below.
// ──────────────────────────────────────────────────────────────────────────────

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const double r = 6371.0;
  final double dLat = (lat2 - lat1) * math.pi / 180.0;
  final double dLng = (lng2 - lng1) * math.pi / 180.0;
  final double lat1R = lat1 * math.pi / 180.0;
  final double lat2R = lat2 * math.pi / 180.0;
  final double sinLat = math.sin(dLat / 2);
  final double sinLng = math.sin(dLng / 2);
  final double a =
      sinLat * sinLat + math.cos(lat1R) * math.cos(lat2R) * sinLng * sinLng;
  return r * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
}

// ──────────────────────────────────────────────────────────────────────────────
// AI Feature 1 — Kalman Filter (GPS smoothing + velocity + ETA)
// Pure Dart, runs entirely on-device, no external service.
// ──────────────────────────────────────────────────────────────────────────────

/// Internal 1-D Kalman filter tracking position + velocity for one axis.
class _KalmanAxis {
  _KalmanAxis({
    required double initialPosition,
    double processNoiseQ = 0.5,
    double measurementNoiseR = 10.0,
  })  : _pos = initialPosition,
        _vel = 0.0,
        _pPos = measurementNoiseR,
        _pVel = 1.0,
        _pCross = 0.0,
        _q = processNoiseQ,
        _r = measurementNoiseR;

  double _pos;
  double _vel;
  double _pPos;
  double _pVel;
  double _pCross;
  final double _q;
  final double _r;

  void update(double measurement, double dt) {
    if (dt <= 0) return;

    // Predict
    final double pPosPred =
        _pPos + dt * (_pCross + _pCross) + dt * dt * _pVel + _q;
    final double pCrossPred = _pCross + dt * _pVel;
    final double pVelPred = _pVel + _q * 0.1;
    final double posPred = _pos + _vel * dt;

    // Update (only position is measured)
    final double s = pPosPred + _r;
    final double kPos = pPosPred / s;
    final double kVel = pCrossPred / s;
    final double innovation = measurement - posPred;

    _pos = posPred + kPos * innovation;
    _vel = _vel + kVel * innovation;
    _pPos = (1.0 - kPos) * pPosPred;
    _pCross = pCrossPred - kPos * pPosPred;
    _pVel = pVelPred - kVel * pCrossPred;
  }

  double get position => _pos;
  double get velocity => _vel; // degrees per second
}

/// A smoothed GPS position produced by [GeofireKalmanFilter].
class GeofireSmoothedPosition {
  GeofireSmoothedPosition({
    required this.latitude,
    required this.longitude,
    required this.velocityLatKmh,
    required this.velocityLngKmh,
    required this.speedKmh,
  });

  final double latitude;
  final double longitude;

  /// North-component of velocity in km/h (positive = northward).
  final double velocityLatKmh;

  /// East-component of velocity in km/h (positive = eastward).
  final double velocityLngKmh;

  /// Scalar speed in km/h derived from both components.
  final double speedKmh;

  /// Extrapolates this position [secondsAhead] seconds into the future
  /// using current velocity. Useful for predictive UI or ETA display.
  GeofireSmoothedPosition predict(double secondsAhead) {
    const double kmPerDegreeLat = 111.32;
    final double kmPerDegreeLng = 111.32 * math.cos(latitude * math.pi / 180.0);
    final double deltaLat =
        (velocityLatKmh / 3600.0) * secondsAhead / kmPerDegreeLat;
    final double deltaLng =
        (velocityLngKmh / 3600.0) * secondsAhead / kmPerDegreeLng;
    return GeofireSmoothedPosition(
      latitude: latitude + deltaLat,
      longitude: longitude + deltaLng,
      velocityLatKmh: velocityLatKmh,
      velocityLngKmh: velocityLngKmh,
      speedKmh: speedKmh,
    );
  }
}

/// On-device Kalman filter that smooths noisy GPS readings and tracks velocity.
///
/// No external service is used. All math runs in Dart on the device.
///
/// Each driver should have its own [GeofireKalmanFilter] instance.
///
/// ```dart
/// final filters = <String, GeofireKalmanFilter>{};
///
/// Geofire.queryAtLocation(lat, lng, radius, includeData: true).listen((event) {
///   final key   = event['key'] as String;
///   final dLat  = (event['latitude']  as num).toDouble();
///   final dLng  = (event['longitude'] as num).toDouble();
///
///   final filter  = filters.putIfAbsent(key, () => GeofireKalmanFilter());
///   final smoothed = filter.update(dLat, dLng);
///
///   print('Speed: ${smoothed.speedKmh.toStringAsFixed(1)} km/h');
///   print('ETA  : ${filter.estimateEtaSeconds(dLat, dLng, riderLat, riderLng)}s');
/// });
/// ```
class GeofireKalmanFilter {
  GeofireKalmanFilter({
    /// Higher value = trusts new measurements more (noisier but responsive).
    double processNoise = 0.5,

    /// GPS horizontal accuracy in metres (lower = smoother but more lag).
    double measurementNoise = 10.0,
  })  : _processNoise = processNoise,
        _measurementNoise = measurementNoise;

  final double _processNoise;
  final double _measurementNoise;

  _KalmanAxis? _latAxis;
  _KalmanAxis? _lngAxis;
  int? _lastTimestampMs;

  /// Feed a raw GPS reading. Returns the smoothed position and estimated velocity.
  ///
  /// [timestampMs] defaults to [DateTime.now().millisecondsSinceEpoch].
  GeofireSmoothedPosition update(double lat, double lng, {int? timestampMs}) {
    final int nowMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

    if (_latAxis == null || _lngAxis == null) {
      _latAxis = _KalmanAxis(
        initialPosition: lat,
        processNoiseQ: _processNoise,
        measurementNoiseR: _measurementNoise,
      );
      _lngAxis = _KalmanAxis(
        initialPosition: lng,
        processNoiseQ: _processNoise,
        measurementNoiseR: _measurementNoise,
      );
      _lastTimestampMs = nowMs;
    } else {
      final double dt = (nowMs - (_lastTimestampMs ?? nowMs)) / 1000.0;
      _latAxis!.update(lat, dt);
      _lngAxis!.update(lng, dt);
      _lastTimestampMs = nowMs;
    }

    const double kmPerDegreeLat = 111.32;
    final double smoothedLat = _latAxis!.position;
    final double kmPerDegreeLng =
        111.32 * math.cos(smoothedLat * math.pi / 180.0);

    final double velLatKmh = _latAxis!.velocity * kmPerDegreeLat * 3600.0;
    final double velLngKmh = _lngAxis!.velocity * kmPerDegreeLng * 3600.0;
    final double speedKmh =
        math.sqrt(velLatKmh * velLatKmh + velLngKmh * velLngKmh);

    return GeofireSmoothedPosition(
      latitude: smoothedLat,
      longitude: _lngAxis!.position,
      velocityLatKmh: velLatKmh,
      velocityLngKmh: velLngKmh,
      speedKmh: speedKmh,
    );
  }

  /// Estimates ETA in seconds for a driver at [driverLat/Lng] to reach
  /// [targetLat/Lng] using the Kalman-estimated speed and straight-line distance.
  ///
  /// Returns `null` if the filter has not been initialised yet or the driver
  /// appears stationary (speed < 0.5 km/h).
  double? estimateEtaSeconds(
    double driverLat,
    double driverLng,
    double targetLat,
    double targetLng,
  ) {
    if (_latAxis == null || _lngAxis == null) return null;

    const double kmPerDegreeLat = 111.32;
    final double kmPerDegreeLng =
        111.32 * math.cos(driverLat * math.pi / 180.0);
    final double velLatKmh = _latAxis!.velocity * kmPerDegreeLat * 3600.0;
    final double velLngKmh = _lngAxis!.velocity * kmPerDegreeLng * 3600.0;
    final double speedKmh =
        math.sqrt(velLatKmh * velLatKmh + velLngKmh * velLngKmh);

    if (speedKmh < 0.5) return null;

    final double distKm =
        _haversineKm(driverLat, driverLng, targetLat, targetLng);
    return (distKm / speedKmh) * 3600.0;
  }

  /// Resets all filter state (e.g. when a driver goes offline then reconnects).
  void reset() {
    _latAxis = null;
    _lngAxis = null;
    _lastTimestampMs = null;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// AI Feature 2 — Velocity Guard (GPS spoof / impossible-jump detection)
// Pure Dart, runs entirely on-device, no external service.
// ──────────────────────────────────────────────────────────────────────────────

/// Result of a [GeofireVelocityGuard.check] call.
class GeofireAnomalyResult {
  GeofireAnomalyResult({
    required this.key,
    required this.isSuspicious,
    required this.speedKmh,
    this.reason,
  });

  /// The driver key that was checked.
  final String key;

  /// `true` when the location jump is physically impossible given [maxSpeedKmh].
  final bool isSuspicious;

  /// Computed speed in km/h between the previous and current reading.
  final double speedKmh;

  /// Human-readable reason when [isSuspicious] is `true`.
  final String? reason;
}

class _DriverSnapshot {
  _DriverSnapshot(this.lat, this.lng, this.timestampMs);
  final double lat;
  final double lng;
  final int timestampMs;
}

/// Detects physically impossible GPS position jumps per driver.
///
/// Works entirely on-device — pure Dart math. No AI service needed.
///
/// ```dart
/// final guard = GeofireVelocityGuard(maxSpeedKmh: 180);
///
/// stream.listen((event) {
///   final result = guard.check(event['key'], lat, lng);
///   if (result.isSuspicious) {
///     print('Possible spoof: ${result.reason}');
///   } else {
///     // trust the location
///   }
/// });
/// ```
class GeofireVelocityGuard {
  GeofireVelocityGuard({
    /// Maximum physically plausible speed for your vehicle type.
    /// Cars: 180–220, motorcycles: 200, walking: 10.
    this.maxSpeedKmh = 200.0,
  });

  final double maxSpeedKmh;
  final Map<String, _DriverSnapshot> _snapshots = <String, _DriverSnapshot>{};

  /// Checks whether the new [lat/lng] for [key] is reachable from the previous
  /// reading within [maxSpeedKmh]. The first call for a key always returns
  /// `isSuspicious: false` (no baseline to compare against yet).
  GeofireAnomalyResult check(String key, double lat, double lng,
      {int? timestampMs}) {
    final int nowMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final _DriverSnapshot? prev = _snapshots[key];

    if (prev == null) {
      _snapshots[key] = _DriverSnapshot(lat, lng, nowMs);
      return GeofireAnomalyResult(key: key, isSuspicious: false, speedKmh: 0.0);
    }

    final double dtHours = (nowMs - prev.timestampMs) / 3600000.0;
    if (dtHours <= 0) {
      return GeofireAnomalyResult(key: key, isSuspicious: false, speedKmh: 0.0);
    }

    final double distKm = _haversineKm(prev.lat, prev.lng, lat, lng);
    final double speedKmh = distKm / dtHours;

    _snapshots[key] = _DriverSnapshot(lat, lng, nowMs);

    if (speedKmh > maxSpeedKmh) {
      return GeofireAnomalyResult(
        key: key,
        isSuspicious: true,
        speedKmh: speedKmh,
        reason:
            'Speed ${speedKmh.toStringAsFixed(1)} km/h exceeds limit of $maxSpeedKmh km/h',
      );
    }

    return GeofireAnomalyResult(
        key: key, isSuspicious: false, speedKmh: speedKmh);
  }

  /// Call when a driver goes offline so their baseline is cleared.
  void remove(String key) => _snapshots.remove(key);

  /// Clears all stored baselines.
  void clear() => _snapshots.clear();
}

// ──────────────────────────────────────────────────────────────────────────────
// AI Feature 3 — Spatial Cluster (dedup bunched drivers)
// Pure Dart greedy radius clustering, no external service.
// ──────────────────────────────────────────────────────────────────────────────

/// A cluster of spatially close [GeofireDriverCandidate]s.
class GeofireCluster {
  GeofireCluster({
    required this.centroidLat,
    required this.centroidLng,
    required this.candidates,
    required this.bestCandidate,
  });

  final double centroidLat;
  final double centroidLng;

  /// All candidates that fell within [GeoFireSpatialCluster.clusterRadiusKm]
  /// of the seed.
  final List<GeofireDriverCandidate> candidates;

  /// The candidate with the highest score inside this cluster.
  final GeofireDriverCandidate bestCandidate;

  int get size => candidates.length;
}

/// Groups a flat list of [GeofireDriverCandidate]s into spatial clusters so
/// that bunched drivers in the same block appear as one entry.
///
/// Uses greedy radius-based grouping — O(n²) but fast for typical
/// driver counts (< 200). Pure Dart, no external service.
///
/// ```dart
/// final candidates = ...; // from queryDriverCandidatesAtLocation
/// final clusters = GeoFireSpatialCluster.cluster(candidates);
/// final topPerCluster = clusters.map((c) => c.bestCandidate).toList();
/// ```
class GeoFireSpatialCluster {
  /// Groups [candidates] into clusters where every member is within
  /// [clusterRadiusKm] kilometres of the seed (highest-score candidate first).
  static List<GeofireCluster> cluster(
    List<GeofireDriverCandidate> candidates, {
    double clusterRadiusKm = 0.5,
  }) {
    // Sort descending by score so the highest-score driver seeds each cluster.
    final List<GeofireDriverCandidate> remaining =
        List<GeofireDriverCandidate>.from(candidates)
          ..sort((GeofireDriverCandidate a, GeofireDriverCandidate b) =>
              b.score.compareTo(a.score));

    final List<GeofireCluster> clusters = <GeofireCluster>[];

    while (remaining.isNotEmpty) {
      final GeofireDriverCandidate seed = remaining.removeAt(0);
      final List<GeofireDriverCandidate> group = <GeofireDriverCandidate>[seed];

      remaining.removeWhere((GeofireDriverCandidate c) {
        final double d = _haversineKm(
            seed.latitude, seed.longitude, c.latitude, c.longitude);
        if (d <= clusterRadiusKm) {
          group.add(c);
          return true;
        }
        return false;
      });

      final double centLat = group
              .map((GeofireDriverCandidate c) => c.latitude)
              .reduce((double a, double b) => a + b) /
          group.length;
      final double centLng = group
              .map((GeofireDriverCandidate c) => c.longitude)
              .reduce((double a, double b) => a + b) /
          group.length;

      final GeofireDriverCandidate best = group.reduce(
          (GeofireDriverCandidate a, GeofireDriverCandidate b) =>
              a.score >= b.score ? a : b);

      clusters.add(GeofireCluster(
        centroidLat: centLat,
        centroidLng: centLng,
        candidates: group,
        bestCandidate: best,
      ));
    }

    return clusters;
  }
}

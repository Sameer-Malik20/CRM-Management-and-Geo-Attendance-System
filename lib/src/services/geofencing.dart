import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/models/office.dart';
import 'package:location/location.dart';

enum GeofenceStatus { init, enter, exit }

class GeoFencing extends InheritedWidget {
  GeoFencing({
    super.key,
    required super.child,
    required this.service,
  });

  final GeoFencingService service;

  @override
  bool updateShouldNotify(InheritedWidget old) => true;

  static GeoFencing of(BuildContext context) {
    final GeoFencing? result =
        context.dependOnInheritedWidgetOfExactType<GeoFencing>();
    assert(result != null, 'No GeoFencingService found in context');
    return result!;
  }
}

class GeoFencingService with ChangeNotifier {
  GeofenceStatus geofenceStatus = GeofenceStatus.init;
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  Office? _office;

  Future<void> startGeofencing(Office office) async {
    _office = office;
    geofenceStatus = GeofenceStatus.init;
    notifyListeners();

    await _locationSubscription?.cancel();

    var serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
    }

    var permissionStatus = await _location.hasPermission();
    if (permissionStatus == PermissionStatus.denied) {
      permissionStatus = await _location.requestPermission();
    }

    if (!serviceEnabled || permissionStatus != PermissionStatus.granted) {
      return;
    }

    _updateStatus(await _location.getLocation());
    _locationSubscription = _location.onLocationChanged.listen(_updateStatus);
  }

  Future<void> stopGeofencing() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    geofenceStatus = GeofenceStatus.init;
    notifyListeners();
  }

  void _updateStatus(LocationData locationData) {
    if (_office == null) {
      return;
    }

    final nextStatus = resolveStatus(_office!, locationData);
    if (nextStatus == GeofenceStatus.init) {
      return;
    }

    if (nextStatus != geofenceStatus) {
      geofenceStatus = nextStatus;
      notifyListeners();
    }
  }

  static GeofenceStatus resolveStatus(Office office, LocationData? locationData) {
    if (locationData == null ||
        locationData.latitude == null ||
        locationData.longitude == null) {
      return GeofenceStatus.init;
    }

    final distance = _distanceInMeters(
      locationData.latitude!,
      locationData.longitude!,
      office.latitude,
      office.longitude,
    );
    return distance <= office.radius ? GeofenceStatus.enter : GeofenceStatus.exit;
  }

  static double _distanceInMeters(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadius = 6371000.0;
    final latitudeDelta = _degreesToRadians(endLatitude - startLatitude);
    final longitudeDelta = _degreesToRadians(endLongitude - startLongitude);
    final startLatInRadians = _degreesToRadians(startLatitude);
    final endLatInRadians = _degreesToRadians(endLatitude);

    final a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(startLatInRadians) *
            math.cos(endLatInRadians) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degree) {
    return degree * math.pi / 180;
  }
}

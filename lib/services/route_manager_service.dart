import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:projectapp/models/bus_route_data.dart';

class RouteManagerService with ChangeNotifier {
  static final RouteManagerService _instance = RouteManagerService._internal();

  factory RouteManagerService() {
    return _instance;
  }

  RouteManagerService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache data
  List<BusStopData> _allStops = [];
  List<BusRouteData> _allRoutes = [];
  bool _isLoadingStops = false;
  bool _isLoadingRoutes = false;
  bool _isUsingDefaultDataStops = true;
  bool _isUsingDefaultDataRoutes = true;

  bool get isLoading => _isLoadingStops || _isLoadingRoutes;
  bool get isUsingDefaultData =>
      _isUsingDefaultDataStops && _isUsingDefaultDataRoutes;
  List<BusStopData> get allStops {
    // ถ้ามีข้อมูลจาก Firestore แล้ว ให้ใช้ข้อมูลจาก Firestore เป็นหลัก
    // แต่ถ้า Firestore ว่างเปล่า (เช่น ยังไม่เคยโหลด) ให้ใช้ Default
    if (_allStops.isNotEmpty) {
      return _allStops;
    }
    return BusStops.all;
  }

  List<BusRouteData> get allRoutes {
    // ถ้ามีข้อมูลจาก Firestore แล้ว ให้ใช้ข้อมูลจาก Firestore เป็นหลัก
    if (_allRoutes.isNotEmpty) {
      return _allRoutes;
    }
    return BusRoutes.all;
  }

  Future<void> initializeData() async {
    await fetchStops();
    await fetchRoutes();
  }

  Future<void> fetchStops() async {
    _isLoadingStops = true;
    notifyListeners();

    try {
      final snapshot = await _firestore.collection('bus_stops').get();
      _allStops = snapshot.docs
          .map((doc) => BusStopData.fromFirestore(doc))
          .toList();
      _isUsingDefaultDataStops = _allStops.isEmpty;
      print('✅ Fetched ${_allStops.length} stops from "Bus stop"');
    } catch (e) {
      print('❌ Error fetching stops: $e');
      _allStops = [];
      _isUsingDefaultDataStops = true;
    } finally {
      _isLoadingStops = false;
      notifyListeners();
    }
  }

  Future<void> fetchRoutes() async {
    _isLoadingRoutes = true;
    notifyListeners();

    try {
      final snapshot = await _firestore.collection('bus_routes').get();

      List<BusRouteData> loadedRoutes = [];

      for (var doc in snapshot.docs) {
        // Fetch path for each route
        List<GeoPoint>? path;
        try {
          final pathSnapshot = await _firestore
              .collection('bus_routes')
              .doc(doc.id)
              .collection('path')
              .doc('main_path')
              .get();

          if (pathSnapshot.exists && pathSnapshot.data() != null) {
            List<dynamic> pointsRaw = pathSnapshot.data()!['points'] ?? [];
            path = pointsRaw.map((p) => p as GeoPoint).toList();
          } else {
            // Fallback to GeoJSON
            path = await _getFallbackPath(doc.id);
          }
        } catch (e) {
          print('Error fetching path for route ${doc.id}: $e');
          path = await _getFallbackPath(doc.id);
        }

        loadedRoutes.add(BusRouteData.fromFirestore(doc, allStops, path: path));
      }

      _allRoutes = loadedRoutes;
      _isUsingDefaultDataRoutes = _allRoutes.isEmpty;
      print('✅ Fetched ${_allRoutes.length} routes from Firestore');
    } catch (e) {
      print('❌ Error fetching routes: $e');
      _allRoutes = [];
      _isUsingDefaultDataRoutes = true;
    } finally {
      _isLoadingRoutes = false;
      notifyListeners();
    }
  }

  // Helper methods equivalent to the static ones in BusRoutes class
  List<BusRouteData> getActiveRoutes(DateTime time) {
    return allRoutes.where((r) => r.isActiveAt(time)).toList();
  }

  List<BusRouteData> getRoutesWithStop(String stopId, {DateTime? time}) {
    final routes = time != null ? getActiveRoutes(time) : allRoutes;
    return routes.where((r) => r.hasStop(stopId)).toList();
  }

  // --- CRUD Operations ---

  Future<void> addStop(BusStopData stop) async {
    await _firestore.collection('bus_stops').doc(stop.id).set(stop.toMap());
    await fetchStops();
  }

  Future<void> updateStop(BusStopData stop) async {
    await _firestore.collection('bus_stops').doc(stop.id).update(stop.toMap());
    await fetchStops();
  }

  Future<void> deleteStop(String id) async {
    await _firestore.collection('bus_stops').doc(id).delete();
    await fetchStops();
  }

  Future<void> addRoute(BusRouteData route, {List<GeoPoint>? path}) async {
    await _firestore
        .collection('bus_routes')
        .doc(route.routeId)
        .set(route.toMap());
    if (path != null) {
      await saveRoutePath(route.routeId, path);
    }
    await fetchRoutes();
  }

  Future<void> updateRoute(BusRouteData route, {List<GeoPoint>? path}) async {
    await _firestore
        .collection('bus_routes')
        .doc(route.routeId)
        .update(route.toMap());
    if (path != null) {
      await saveRoutePath(route.routeId, path);
    }
    await fetchRoutes();
  }

  Future<void> saveRoutePath(String routeId, List<GeoPoint> points) async {
    await _firestore
        .collection('bus_routes')
        .doc(routeId)
        .collection('path')
        .doc('main_path')
        .set({'points': points});
    await fetchRoutes();
  }

  Future<void> deleteRoute(String routeId) async {
    await _firestore.collection('bus_routes').doc(routeId).delete();
    await fetchRoutes();
  }

  /// ลบป้ายรถเมล์ทั้งหมดใน Firestore
  Future<void> deleteAllStops() async {
    final snapshot = await _firestore.collection('bus_stops').get();
    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    await fetchStops();
  }

  /// ลบสายรถทั้งหมดใน Firestore
  Future<void> deleteAllRoutes() async {
    final snapshot = await _firestore.collection('bus_routes').get();
    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    await fetchRoutes();
  }

  /// ลบประวัติการเดินรถทั้งหมดใน Firestore
  Future<void> deleteAllOperationLogs() async {
    final snapshot = await _firestore.collection('bus_operation_logs').get();
    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// ลบข้อมูลความคิดเห็น (Feedback) ทั้งหมดใน Firestore
  Future<void> deleteAllFeedbacks() async {
    final snapshot = await _firestore.collection('feedback').get();
    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // --- Helper methods ---
  BusStopData? getStopFromId(String id) {
    try {
      return allStops.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> importDefaults() async {
    // 1. Import Stops
    for (var stop in BusStops.all) {
      await _firestore
          .collection('bus_stops')
          .doc(stop.id)
          .set(stop.toMap(), SetOptions(merge: true));
    }
    // 2. Import Routes (Metadata)
    for (var route in BusRoutes.all) {
      await _firestore
          .collection('bus_routes')
          .doc(route.routeId)
          .set(route.toMap(), SetOptions(merge: true));
    }
    await initializeData();
  }

  Future<List<GeoPoint>?> _getFallbackPath(String routeId) async {
    String assetPath = '';
    if (routeId == 'S1-PM')
      assetPath = 'assets/data/bus_route1_pm.geojson';
    else if (routeId == 'S1-AM' || routeId == 'S1')
      assetPath = 'assets/data/bus_route1_am.geojson';
    else if (routeId.contains('S2'))
      assetPath = 'assets/data/bus_route2.geojson';
    else if (routeId.contains('S3'))
      assetPath = 'assets/data/bus_route3.geojson';

    if (assetPath.isEmpty) return null;

    try {
      final data = await rootBundle.loadString(assetPath);
      final json = jsonDecode(data);
      final List<GeoPoint> points = [];
      final features = json['features'] as List;
      if (features.isNotEmpty) {
        final geometry = features.first['geometry'];
        final coordinates = geometry['coordinates'] as List;
        if (geometry['type'] == 'MultiLineString') {
          for (var line in coordinates) {
            for (var p in line)
              points.add(
                GeoPoint((p[1] as num).toDouble(), (p[0] as num).toDouble()),
              );
          }
        } else if (geometry['type'] == 'LineString') {
          for (var p in coordinates)
            points.add(
              GeoPoint((p[1] as num).toDouble(), (p[0] as num).toDouble()),
            );
        }
      }
      return points;
    } catch (e) {
      print('Fallback path error for $routeId: $e');
      return null;
    }
  }
}

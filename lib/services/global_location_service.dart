import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Add this import
import 'dart:convert'; // For jsonDecode
import 'package:flutter/services.dart' show rootBundle; // For loading assets
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_model.dart';
import 'notification_service.dart';
import 'route_service.dart';
import 'route_manager_service.dart';

/// Global service สำหรับ location tracking และแจ้งเตือนรถใกล้ถึง
/// ทำงานตลอดเวลาไม่ว่าจะอยู่หน้าไหนก็ตาม
class GlobalLocationService extends ChangeNotifier {
  static final GlobalLocationService _instance =
      GlobalLocationService._internal();
  factory GlobalLocationService() => _instance;

  // พิกัดจุดพักรถ (Rest Stops) - รัศมี 150 เมตร
  final List<LatLng> _restStops = const [
    LatLng(19.030639, 99.923262), // Zone A (หอพัก)
    LatLng(19.030798, 99.923198),
    LatLng(19.022599, 99.895530), // Zone B (หน้ามอ)
    LatLng(19.025462, 99.894947),
    LatLng(19.025604, 99.894740),
  ];

  List<LatLng> get restStops => _restStops;

  // ระยะทางที่ยอมรับได้สำหรับจุดพักรถ (เมตร)
  static const double _restStopRadius = 150.0;

  GlobalLocationService._internal();

  // State
  LatLng? _userPosition;
  List<Bus> _buses = [];
  Bus? _closestBus;
  Bus? _targetBus; // เพิ่ม: สำหรับเก็บรถเป้าหมายที่กำลังแจ้งเตือน/ติดตาม
  List<Map<String, dynamic>> _allBusStops = [];
  bool _notifyEnabled = false;
  String? _selectedNotifyRouteId;
  bool _isInitialized = false;
  Set<String> _allKnownBusIds = {}; // เก็บไอดีรถทั้งหมดที่รู้จักจาก RTDB

  // New State for Destination
  String? _destinationName;
  String? _destinationRouteId;
  final Map<String, double> _prevDistToDest =
      {}; // เก็บระยะห่างจากปลายทางครั้งก่อน
  final Map<String, int> _lastAlertStage =
      {}; // เก็บระดับการแจ้งเตือนล่าสุดของแต่ละคัน (0=ยังไม่แจ้ง, 1=5นาที, 2=3นาที, 3=1นาที, 4=ถึงแล้ว)

  // Off-Route Detection
  final Map<String, List<LatLng>> _routePaths = {}; // Cached route paths
  static const double _offRouteThresholdMeters = 50.0;

  // Snap-to-Route Interpolation
  final Map<String, LatLng> _displayedPositions =
      {}; // ตำแหน่งที่แสดงบน UI (smooth)
  final Map<String, Timer> _interpTimers = {}; // timer ต่อคัน
  final Map<String, bool> _recentOffRoutes = {}; // Track off-route status
  DateTime? _lastAggregatedOffRouteAlert;
  Set<String> _lastOffRouteBusIds = {};
  static const int _aggregatedManagerAlertId = 9999;

  // ─── Green Route PKY Config ───────────────────────────────────────────────
  /// โหมดการวิ่งเข้า PKY ของสายหน้ามอ
  /// 'none' = ไม่เข้าตลอดวัน, 'always' = เข้าตลอดวัน, 'custom' = กำหนดเวลาเอง
  String _greenPkyMode = 'custom'; // default = เดิม (14:00)
  int _greenPkyStartHour = 14;
  int _greenPkyStartMinute = 0;
  StreamSubscription? _routeConfigSubscription;
  // ──────────────────────────────────────────────────────────────────────────

  // Subscriptions
  StreamSubscription? _busSubscription;
  StreamSubscription<Position>? _positionSubscription;

  // Constants
  static const double _alertDistanceMeters = 250.0; // ระยะ "มาถึงแล้ว"
  static const double _stopProximityMeters = 50.0;

  // Getters
  LatLng? get userPosition => _userPosition;
  bool isOffRoute(String busId) => _recentOffRoutes.containsKey(busId);

  /// Getter สำหรับ config PKY (ให้ UI อ่านค่าได้)
  String get greenPkyMode => _greenPkyMode;
  int get greenPkyStartHour => _greenPkyStartHour;
  int get greenPkyStartMinute => _greenPkyStartMinute;

  /// คืน true ถ้า ณ ตอนนี้สายหน้ามอควรวิ่งเข้า PKY
  bool isGreenPKYActive() {
    switch (_greenPkyMode) {
      case 'always':
        return true;
      case 'none':
        return false;
      case 'custom':
      default:
        final now = DateTime.now();
        final nowMins = now.hour * 60 + now.minute;
        final startMins = _greenPkyStartHour * 60 + _greenPkyStartMinute;
        return nowMins >= startMins;
    }
  }

  /// คืน buses พร้อมตำแหน่งที่ smooth แล้ว (snap-to-route)
  List<Bus> get buses {
    if (_displayedPositions.isEmpty) return _buses;
    return _buses.map((bus) {
      final displayed = _displayedPositions[bus.id];
      if (displayed != null) return bus.copyWithPosition(displayed);
      return bus;
    }).toList();
  }

  Bus? get closestBus => _closestBus;
  Bus? get targetBus => _targetBus; // เพิ่ม getter
  List<Map<String, dynamic>> get allBusStops => _allBusStops;
  bool get notifyEnabled => _notifyEnabled;
  String? get selectedNotifyRouteId => _selectedNotifyRouteId;
  bool get isInitialized => _isInitialized;
  Set<String> get allKnownBusIds => _allKnownBusIds;
  String? get destinationName => _destinationName;
  String? get destinationRouteId => _destinationRouteId;

  Future<void> _startLocationTracking() async {
    debugPrint("📡 [GlobalLocationService] Starting location tracking...");

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint("❌ [GlobalLocationService] Location service is DISABLED!");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint("❌ [GlobalLocationService] Permission DENIED!");
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint("❌ [GlobalLocationService] Permission DENIED FOREVER!");
      return;
    }

    // --- ดึงพิกัดเริ่มต้นทันทีเพื่อให้ระบบมีข้อมูล User Position ทันที ---
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _userPosition = LatLng(position.latitude, position.longitude);
      _updateClosestBus();
      notifyListeners();
      debugPrint(
        "📍 [GlobalLocationService] Initial position: ${_userPosition!.latitude}, ${_userPosition!.longitude}",
      );
    } catch (e) {
      debugPrint("❌ [GlobalLocationService] Initial position error: $e");
    }
    // -----------------------------------------------------------

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          (Position position) {
            _userPosition = LatLng(position.latitude, position.longitude);
            _updateClosestBus();
            notifyListeners();
          },
          onError: (e) {
            debugPrint("❌ [GlobalLocationService] Location Stream Error: $e");
          },
        );
  }

  /// เริ่มต้น service (เรียกครั้งเดียวตอน app start)
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint("🚀 [GlobalLocationService] Initializing...");

    await NotificationService.initialize();

    // ดึงข้อมูลจาก RouteManagerService เป็นหลัก
    final routeManager = RouteManagerService();
    await routeManager.initializeData();

    // ฟังการเปลี่ยนจาก Editor เผื่อมีการแก้ไขระหว่างใช้งาน
    routeManager.addListener(_syncDataWithRouteManager);

    _syncDataWithRouteManager(); // Sync ครั้งแรก

    _listenToGreenRouteConfig(); // Listen to PKY config from Firestore
    _listenToBusLocation();
    await _startLocationTracking();

    _isInitialized = true;
    debugPrint("✅ [GlobalLocationService] Initialized successfully");
  }

  void _syncDataWithRouteManager() {
    final routeManager = RouteManagerService();

    // Sync ป้ายรถ
    _allBusStops = routeManager.allStops.map((stop) {
      return {
        'id': stop.id,
        'name': stop.name,
        'lat': stop.location?.latitude ?? 0.0,
        'long': stop.location?.longitude ?? 0.0,
        'route_id': null, // ป้ายกลางใช้ร่วมกันหลายสาย
      };
    }).toList();

    // Sync พิกัดเส้นทาง
    _routePaths.clear();
    for (var route in routeManager.allRoutes) {
      if (route.pathPoints != null && route.pathPoints!.isNotEmpty) {
        _routePaths[route.routeId] = route.pathPoints!
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
      } else {
        // Fallback to GeoJSON assets if no cloud path exists
        _loadSingleFallbackPath(route.routeId);
      }
    }

    debugPrint(
      "🔄 [GlobalLocationService] Synced with RouteManager: ${_allBusStops.length} stops, ${_routePaths.length} paths",
    );
    notifyListeners();
  }

  Future<void> _loadSingleFallbackPath(String routeId) async {
    String assetPath = '';
    if (routeId == 'S1-PM')
      assetPath = 'assets/data/bus_route1_pm.geojson';
    else if (routeId == 'S1-AM' || routeId == 'S1')
      assetPath = 'assets/data/bus_route1_am.geojson';
    else if (routeId.contains('S2'))
      assetPath = 'assets/data/bus_route2.geojson';
    else if (routeId.contains('S3'))
      assetPath = 'assets/data/bus_route3.geojson';

    if (assetPath.isNotEmpty) {
      try {
        final points = await _parseGeoJsonToPoints(assetPath);
        if (points.isNotEmpty) {
          _routePaths[routeId] = points;
        }
      } catch (e) {
        debugPrint("Error loading fallback for $routeId: $e");
      }
    }
  }

  /// ฟังค่า config PKY สายหน้ามอจาก Firestore แบบ real-time
  void _listenToGreenRouteConfig() {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month}-${now.day}";
    _routeConfigSubscription?.cancel();
    _routeConfigSubscription = FirebaseFirestore.instance
        .collection('route_config')
        .doc(dateStr)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            // ไม่มี config วันนี้ → ใช้ default
            _greenPkyMode = 'custom';
            _greenPkyStartHour = 14;
            _greenPkyStartMinute = 0;
          } else {
            final data = snapshot.data()!;
            _greenPkyMode = data['green_pky_mode']?.toString() ?? 'custom';
            _greenPkyStartHour =
                (data['green_pky_start_hour'] as num?)?.toInt() ?? 14;
            _greenPkyStartMinute =
                (data['green_pky_start_minute'] as num?)?.toInt() ?? 0;
          }
          debugPrint(
            "📋 [GreenRoute] PKY config: mode=$_greenPkyMode "
            "start=$_greenPkyStartHour:${_greenPkyStartMinute.toString().padLeft(2, '0')}",
          );
          // เมื่อ config เปลี่ยน ให้ recheck off-route ทันที
          _checkOffRouteStatus();
          notifyListeners();
        });
  }

  /// เปิด/ปิดการแจ้งเตือน
  void setNotifyEnabled(bool enabled, {String? routeId}) {
    _notifyEnabled = enabled;
    _selectedNotifyRouteId = routeId;
    _lastAlertStage.clear(); // Reset history

    // เรียกคำนวณใหม่ทันทีเพื่อไม่ให้ค้างสถานะ "ไม่พบรถ"
    _updateClosestBus();

    notifyListeners();
    debugPrint(
      "🔔 [GlobalLocationService] Notify enabled: $enabled, routeId: $routeId",
    );
  }

  /// ตั้งค่าจุดหมายปลายทาง (ถ้า name เป็น null คือยกเลิก)
  void setDestination(String? name, String? routeId) {
    _destinationName = name;
    _destinationRouteId = routeId;
    _prevDistToDest.clear(); // Reset history
    _lastAlertStage.clear(); // Reset alert history

    // ถ้ามีการเลือกปลายทาง ให้เปิดแจ้งเตือนอัตโนมัติสำหรับสายนั้น
    if (name != null && routeId != null) {
      _notifyEnabled = true;
      _selectedNotifyRouteId = routeId;
      debugPrint(
        "🎯 [GlobalLocationService] Source set to $name (Route: $routeId)",
      );
    } else {
      // ถ้ายกเลิก ก็ปิด notify ด้วยเพื่อป้องกัน fallback ไป "แจ้งเตือนทุกสาย"
      _notifyEnabled = false;
      _selectedNotifyRouteId = null;
      debugPrint(
        "❌ [GlobalLocationService] Destination cleared and notifications disabled",
      );
    }

    _updateClosestBus(); // Recalculate immediately
    notifyListeners();
  }

  /// คืนค่าพิกัดของจุดหมายปลายทาง (ถ้ามี)
  LatLng? get destinationPosition {
    if (_destinationName == null || _allBusStops.isEmpty) return null;
    try {
      final stop = _allBusStops.firstWhere(
        (s) => s['name'] == _destinationName,
      );
      return LatLng(stop['lat'], stop['long']);
    } catch (e) {
      return null;
    }
  }

  // _fetchBusStops is removed as it's now handled by _syncDataWithRouteManager

  /// ฟังตำแหน่งรถจาก Firebase Realtime Database
  void _listenToBusLocation() {
    final gpsRef = FirebaseDatabase.instance.ref("GPS");
    _busSubscription = gpsRef.onValue.listen((event) {
      final data = event.snapshot.value;
      if (data == null) return;

      // เก็บ bus เดิมไว้เพื่อ reuse object และเช็ค movement
      final prevMap = {for (var b in _buses) b.id: b};

      List<Bus> newBuses = [];
      bool anyChanged = false;

      if (data is Map) {
        // อัปเดตรายชื่อรถทั้งหมดที่มีใน RTDB (ดึงจาก keys)
        final keys = data.keys.map((k) => k.toString()).toSet();
        if (keys.any((k) => k == 'lat' || k == 'lng')) {
          // กรณีโครงสร้างข้อมูลแบบเก่า (ตัวอย่างเดียว)
          _allKnownBusIds.add('bus_1');
        } else {
          _allKnownBusIds.addAll(keys);
        }

        data.forEach((key, value) {
          if (value is Map &&
              value.containsKey('lat') &&
              value.containsKey('lng')) {
            try {
              final fresh = Bus.fromFirebase(key.toString(), value);
              final prev = prevMap[fresh.id];

              if (prev == null) {
                // รถใหม่
                newBuses.add(fresh);
                anyChanged = true;
              } else {
                // ตรวจว่าขยับเกิน 2 เมตรไหม
                const dist = Distance();
                final moved = dist.as(
                  LengthUnit.Meter,
                  prev.position,
                  fresh.position,
                );
                if (moved >= 2.0) {
                  newBuses.add(fresh); // ใช้ตำแหน่งใหม่
                  anyChanged = true;
                } else {
                  newBuses.add(
                    prev,
                  ); // ใช้ object เดิม — AnimatedMarker ไม่ warp
                }
              }
            } catch (e) {
              debugPrint('Error parsing bus $key: $e');
            }
          }
        });

        if (newBuses.isEmpty &&
            data.containsKey('lat') &&
            data.containsKey('lng')) {
          newBuses.add(Bus.fromFirebase('bus_1', data));
          anyChanged = true;
        }
      }

      // เรียง list ให้ stable ตาม bus id — ป้องกัน key mismatch
      newBuses.sort((a, b) => a.id.compareTo(b.id));

      if (anyChanged || newBuses.length != prevMap.length) {
        _buses = newBuses; // อัปเดต list หลักก่อน
        _checkOffRouteStatus();

        // เรียก smooth interpolation สำหรับรถที่ตำแหน่งเปลี่ยน
        for (final bus in newBuses) {
          final prev = prevMap[bus.id];
          // interpolate เฉพาะรถที่ตำแหน่งเปลี่ยน (หรือรถใหม่)
          if (prev == null || prev.position != bus.position) {
            _interpolateAlongRoute(bus);
          }
        }
        _updateClosestBus(); // ไม่ต้อง notify ตรงนี้ เพราะ _updateClosestBus จะเรียกให้ตอนเสร็จ
      }
    });
  }

  List<LatLng>? _getRoutePathForColor(String routeColor) {
    final c = routeColor.toLowerCase();

    // จัดการสายหน้ามอ (S1) ที่มีเงื่อนไข PKY เป็นพิเศษ
    if (c.contains('green') || c.contains('เขียว') || c.contains('s1')) {
      return isGreenPKYActive() ? _routePaths['S1-PM'] : _routePaths['S1-AM'];
    }

    // พยายามหาจาก ID ที่ตรงกันใน Cache (ถ้ามีคีย์ตรงๆ เช่น 'S2', 'S3')
    for (var key in _routePaths.keys) {
      if (c.contains(key.toLowerCase()) || key.toLowerCase().contains(c)) {
        return _routePaths[key];
      }
    }

    return null;
  }

  /// แมป route_id ของป้าย → key ของ _routePaths
  List<LatLng>? _getRoutePathForStopRouteId(String? routeId) {
    if (routeId == null) return null;
    final r = routeId.toLowerCase();

    if (r.contains('green') || r.contains('s1') || r.contains('เขียว')) {
      return isGreenPKYActive() ? _routePaths['S1-PM'] : _routePaths['S1-AM'];
    }

    // ค้นหาแบบ Dynamic
    if (_routePaths.containsKey(routeId)) return _routePaths[routeId];

    for (var key in _routePaths.keys) {
      if (r.contains(key.toLowerCase()) || key.toLowerCase().contains(r)) {
        return _routePaths[key];
      }
    }
    return null;
  }

  /// คำนวณรถที่ใกล้ที่สุดและแจ้งเตือน
  Future<void> _updateClosestBus() async {
    if (_buses.isEmpty || _userPosition == null) {
      if (_buses.isEmpty)
        debugPrint("DEBUG: _updateClosestBus - _buses is EMPTY");
      if (_userPosition == null)
        debugPrint("DEBUG: _updateClosestBus - _userPosition is NULL");
      return;
    }

    final Distance distance = const Distance();

    // 1. หาป้ายที่ใกล้ตัวเราที่สุด (เพื่อดู Context ว่าเราอยู่ที่ป้ายหรือเปล่า)
    Map<String, dynamic>? closestStopToUser;
    double userDistToClosestStop = double.infinity;
    String closestStopName = "ไม่ทราบชื่อ";

    if (_allBusStops.isNotEmpty) {
      for (var stop in _allBusStops) {
        final stopPos = LatLng(stop['lat'], stop['long']);
        // ใช้ระยะทางจริง (Route Distance) ถ้าทำได้
        final d = _calculateDistanceToStop(
          stopPos,
          stop['route_id']?.toString(),
        );
        if (d < userDistToClosestStop) {
          userDistToClosestStop = d;
          closestStopToUser = stop;
        }
      }
      if (closestStopToUser != null) {
        closestStopName = closestStopToUser['name'].toString();
      }
    }

    // 2. เช็คว่า "เราอยู่ที่ป้ายไหม?" (ระยะห่างตามถนน <= 50 เมตร)
    // แต่ตอนนี้เราจะใช้ closestStopToUser เป็น target หลักในการแจ้งเตือนเสมอ
    // ถ้าเราอยู่ใกล้ป้าย (< 50m) ก็ถือว่ารอที่ป้าย
    final bool isUserAtStop =
        closestStopToUser != null &&
        userDistToClosestStop <= _stopProximityMeters;

    List<Bus> busesWithDistance = [];

    for (final bus in _buses) {
      // คำนวณระยะทางสำหรับรถคันนี้
      double distToTarget;

      // เราต้องใช้ Route Path ของรถคันนั้นๆ ในการวัดระยะเสมอ
      final routePath = _getRoutePathForColor(bus.routeColor);

      if (closestStopToUser != null) {
        // กรณีใหม่: ยึด "ป้ายที่ใกล้ที่สุด" เป็นหลักเสมอ
        // วัดระยะ "รถ -> ป้ายที่ใกล้ที่สุด"
        final stopPos = LatLng(
          closestStopToUser['lat'],
          closestStopToUser['long'],
        );

        double? polyDist;
        if (routePath != null && routePath.length >= 2) {
          polyDist = RouteService.getPolylineDistance(
            bus.position,
            stopPos,
            routePath,
          );
        }
        distToTarget =
            polyDist ?? distance.as(LengthUnit.Meter, bus.position, stopPos);
      } else {
        // กรณีสำรอง: หาป้ายไม่เจอจริงๆ ค่อยวัด "รถ -> เรา"
        double? polyDist;
        if (routePath != null && routePath.length >= 2) {
          polyDist = RouteService.getPolylineDistance(
            _userPosition!,
            bus.position,
            routePath,
          );
        }
        distToTarget =
            polyDist ??
            distance.as(LengthUnit.Meter, _userPosition!, bus.position);
      }

      busesWithDistance.add(bus.copyWithDistance(distToTarget));
    }

    // 3. เรียงลำดับรถตามระยะทางเพื่อให้คันที่ใกล้ที่สุดอยู่ลำดับแรก
    busesWithDistance.sort(
      (a, b) => (a.distanceToUser ?? double.infinity).compareTo(
        b.distanceToUser ?? double.infinity,
      ),
    );

    // กำหนด _closestBus (แบบ Global)
    _closestBus = busesWithDistance.isNotEmpty ? busesWithDistance.first : null;

    // 4. กำหนด _targetBus ตามเงื่อนไขการแจ้งเตือน
    _targetBus = null;

    if (_notifyEnabled) {
      if (_destinationName != null &&
          _destinationRouteId != null &&
          destinationPosition != null) {
        // กรณีเลือกปลายทาง
        final targetId = _destinationRouteId!.trim().toLowerCase();
        final destPos = destinationPosition!;

        var candidateBuses = busesWithDistance.where((b) {
          return isBusMatchRoute(b, targetId);
        }).toList();

        // Sort candidates too
        candidateBuses.sort(
          (a, b) => (a.distanceToUser ?? double.infinity).compareTo(
            b.distanceToUser ?? double.infinity,
          ),
        );

        Bus? approachingBus;
        double minDistance = double.infinity;

        for (var bus in candidateBuses) {
          double distToDest = distance.as(
            LengthUnit.Meter,
            bus.position,
            destPos,
          );
          if (_prevDistToDest.containsKey(bus.id)) {
            if (distToDest <= _prevDistToDest[bus.id]!) {
              if ((bus.distanceToUser ?? double.infinity) < minDistance) {
                minDistance = bus.distanceToUser ?? double.infinity;
                approachingBus = bus;
              }
            }
          } else {
            if ((bus.distanceToUser ?? double.infinity) < minDistance) {
              minDistance = bus.distanceToUser ?? double.infinity;
              approachingBus = bus;
            }
          }
          _prevDistToDest[bus.id] = distToDest;
        }
        _targetBus = approachingBus;
      } else if (_selectedNotifyRouteId != null) {
        // กรณีเลือกเฉพาะสาย
        final targetFilter = _selectedNotifyRouteId!.trim().toLowerCase();
        final filteredBuses = busesWithDistance.where((b) {
          return isBusMatchRoute(b, targetFilter);
        }).toList();

        // Sort filtered buses
        filteredBuses.sort(
          (a, b) => (a.distanceToUser ?? double.infinity).compareTo(
            b.distanceToUser ?? double.infinity,
          ),
        );

        _targetBus = filteredBuses.isNotEmpty ? filteredBuses.first : null;
      } else {
        // กรณีทุกสาย
        _targetBus = _closestBus;
      }

      // --- Debug Info ---
      if (_targetBus != null) {
        final dist = _targetBus!.distanceToUser ?? 0;
        final eta = NotificationService.calculateEtaSeconds(dist);
        debugPrint(
          "🎯 [GlobalLocationService] Tracking Target: ${_targetBus!.id} (${_targetBus!.routeId}) - Dist: ${dist.toStringAsFixed(0)}m, ETA: $eta s",
        );
      } else {
        debugPrint(
          "🔍 [GlobalLocationService] No target bus found. (Total buses: ${busesWithDistance.length})",
        );
      }

      // --- แจ้งเตือน (Notification / Push) ---
      if (_targetBus != null) {
        final targetBus = _targetBus!;
        final targetDist = targetBus.distanceToUser ?? double.infinity;
        final etaSeconds = NotificationService.calculateEtaSeconds(targetDist);
        final busId = targetBus.id;
        final lastStage = _lastAlertStage[busId] ?? 0;

        // เตรียม Context ข้อความ
        String contextMsg = closestStopToUser != null
            ? "ป้าย$closestStopName"
            : "คุณ";
        if (closestStopToUser != null && !isUserAtStop)
          contextMsg += " (ป้ายใกล้คุณ)";

        // เช็ค Stage การแจ้งเตือน (Push Alert)
        if (targetDist <= _alertDistanceMeters && lastStage < 4) {
          _sendArrivalAlert(
            targetBus,
            targetDist,
            etaSeconds,
            contextMsg,
            isUserAtStop,
          );
          _lastAlertStage[busId] = 4;
        } else if (etaSeconds <= 60 && lastStage < 3) {
          _sendArrivalAlert(
            targetBus,
            targetDist,
            etaSeconds,
            contextMsg,
            isUserAtStop,
          );
          _lastAlertStage[busId] = 3;
        } else if (etaSeconds <= 180 && lastStage < 2) {
          _sendArrivalAlert(
            targetBus,
            targetDist,
            etaSeconds,
            contextMsg,
            isUserAtStop,
          );
          _lastAlertStage[busId] = 2;
        } else if (etaSeconds <= 300 && lastStage < 1) {
          _sendArrivalAlert(
            targetBus,
            targetDist,
            etaSeconds,
            contextMsg,
            isUserAtStop,
          );
          _lastAlertStage[busId] = 1;
        }
      }
    }

    _buses = busesWithDistance; // อัปเดตลิสต์ที่มีระยะทางแล้ว
    notifyListeners();
  }

  Future<void> _sendArrivalAlert(
    Bus bus,
    double dist,
    int eta,
    String locationContext,
    bool isAtStop,
  ) async {
    String colorName = "รถ";
    final rId = bus.routeId.toLowerCase();
    if (rId.contains("green"))
      colorName = "สีเขียว";
    else if (rId.contains("red"))
      colorName = "สีแดง";
    else if (rId.contains("blue"))
      colorName = "สีน้ำเงิน";
    else if (rId.contains("purple"))
      colorName = "สีม่วง";

    // Format Title
    String title = "🚌 รถ$colorName กำลังมา!";

    // Format Body
    String timeText = (eta <= 0 || dist < 50)
        ? "ถึงแล้ว"
        : "อีก ${NotificationService.formatEta(eta)}";

    String body;
    if (dist < 50) {
      body = isAtStop ? "รถแวะจอดที่$locationContext แล้ว" : "รถถึงตัวคุณแล้ว";
    } else {
      body = "$timeText จะถึง$locationContext";
    }

    if (_destinationName != null) {
      body += " (ไป: $_destinationName)";
    }

    // เรียกใช้ showNotification โดยตรงเพื่อให้ Custom Body ได้เต็มที่
    await NotificationService.showNotification(
      id: bus.id.hashCode,
      title: title,
      body: "$body (ห่าง ${dist.toStringAsFixed(0)} ม.)",
      payload: "bus_${bus.id}",
    );
    await NotificationService.vibrate();

    debugPrint("🔔 Alert: $title - $body");
  }

  /// คำนวณระยะทางไปยังป้ายรถตาม polyline (ถ้ามี route path)
  double _calculateDistanceToStop(LatLng stopPos, String? routeId) {
    if (_userPosition == null) return double.infinity;
    final Distance distance = const Distance();
    final routePath = _getRoutePathForStopRouteId(routeId);
    if (routePath != null && routePath.length >= 2) {
      final polyDist = RouteService.getPolylineDistance(
        _userPosition!,
        stopPos,
        routePath,
      );
      if (polyDist != null) return polyDist;
    }
    // Fallback เป็น Haversine
    return distance.as(LengthUnit.Meter, _userPosition!, stopPos);
  }

  /// คำนวณหาป้ายที่ใกล้ที่สุด
  String getClosestStopInfo() {
    if (_userPosition == null) return "รอ GPS...";
    if (_allBusStops.isEmpty) return "ไม่มีข้อมูลป้าย";

    double closestDist = double.infinity;
    String? closestName;

    for (var stop in _allBusStops) {
      final stopPos = LatLng(stop['lat'], stop['long']);
      final dist = _calculateDistanceToStop(
        stopPos,
        stop['route_id']?.toString(),
      );
      if (dist < closestDist) {
        closestDist = dist;
        closestName = stop['name'];
      }
    }

    if (closestName == null) return "ไม่พบ";
    return "$closestName (${closestDist.toStringAsFixed(0)}m)";
  }

  /// คืนค่า Map ของป้ายที่ใกล้ที่สุด
  Map<String, dynamic>? findClosestStop() {
    if (_userPosition == null || _allBusStops.isEmpty) return null;

    double closestDist = double.infinity;
    Map<String, dynamic>? closestStop;

    for (var stop in _allBusStops) {
      final stopPos = LatLng(stop['lat'], stop['long']);
      final dist = _calculateDistanceToStop(
        stopPos,
        stop['route_id']?.toString(),
      );
      if (dist < closestDist) {
        closestDist = dist;
        closestStop = stop;
      }
    }

    return closestStop;
  }

  // --- Off-Route Detection Logic ---

  // _loadRoutePaths is replaced by _syncDataWithRouteManager

  // --- Snap-to-Route Interpolation Helpers ---

  /// เลือก route path ตามสีรถและ PKY config (config-aware)
  List<LatLng>? _getRoutePathForBus(Bus bus) {
    final rId = bus.routeId.toLowerCase();
    final rColor = bus.routeColor.toLowerCase();

    // ลอจิกสาย S1 (เขียว)
    if (rId.contains('s1') ||
        rColor.contains('green') ||
        rColor.contains('เขียว')) {
      return isGreenPKYActive() ? _routePaths['S1-PM'] : _routePaths['S1-AM'];
    }

    // ลองหาจาก routeId ตรงๆ (Firestore ID)
    if (_routePaths.containsKey(bus.routeId)) {
      return _routePaths[bus.routeId];
    }

    // ลองหาจากชื่อที่ใกล้เคียง
    for (var key in _routePaths.keys) {
      if (rId.contains(key.toLowerCase()) || key.toLowerCase().contains(rId)) {
        return _routePaths[key];
      }
    }

    return null;
  }

  /// Snap ตำแหน่งลง route — คืน (snappedPoint, distanceMeters)
  ({LatLng snapped, double dist}) _snapToRoute(LatLng pos, List<LatLng> path) {
    const distance = Distance();
    LatLng closest = path.first;
    double minDist = double.infinity;
    for (final point in path) {
      final d = distance.as(LengthUnit.Meter, pos, point);
      if (d < minDist) {
        minDist = d;
        closest = point;
      }
    }
    return (snapped: closest, dist: minDist);
  }

  /// หา index ที่ใกล้ point ที่สุดใน path
  int _closestIndex(LatLng point, List<LatLng> path) {
    const distance = Distance();
    int best = 0;
    double minDist = double.infinity;
    for (int i = 0; i < path.length; i++) {
      final d = distance.as(LengthUnit.Meter, point, path[i]);
      if (d < minDist) {
        minDist = d;
        best = i;
      }
    }
    return best;
  }

  /// เริ่ม smooth interpolation สำหรับ bus 1 คัน
  /// - ถ้า on-route: step ผ่าน waypoints บน polyline
  /// - ถ้า off-route: ใช้ raw GPS ให้ manager เห็นชัด
  void _interpolateAlongRoute(Bus bus) {
    // 1. ถ้าอยู่ในจุดพักรถ -> ถือว่าปกติ (ไม่ Off-route)
    if (_isBusInRestStop(bus)) {
      if (_recentOffRoutes.containsKey(bus.id)) {
        _recentOffRoutes.remove(bus.id);
        notifyListeners();
      }
      // ยังคง update position ให้เห็นรถขยับในจุดพัก
      _displayedPositions[bus.id] = bus.position;
      notifyListeners();
      return;
    }

    final path = _getRoutePathForBus(bus);
    if (path == null || path.isEmpty) {
      // ไม่รู้ route -> แสดง raw GPS
      _displayedPositions[bus.id] = bus.position;
      notifyListeners();
      return;
    }

    // Snap to route
    final snap = _snapToRoute(bus.position, path);

    // Check Off-route
    if (snap.dist > _offRouteThresholdMeters) {
      if (!_recentOffRoutes.containsKey(bus.id)) {
        _recentOffRoutes[bus.id] = true;
        // แจ้งเตือน Off-route (ถ้าต้องการ)
      }
      _interpTimers[bus.id]?.cancel();
      _displayedPositions[bus.id] = bus.position;
      notifyListeners();
      return;
    }

    // On-route: Clear alert
    if (_recentOffRoutes.containsKey(bus.id)) {
      _recentOffRoutes.remove(bus.id);
      notifyListeners();
    }

    // Interpolate logic
    final prevDisplayed = _displayedPositions[bus.id] ?? snap.snapped;
    final fromIdx = _closestIndex(prevDisplayed, path);
    final toIdx = _closestIndex(snap.snapped, path);

    List<LatLng> waypoints;
    if (fromIdx <= toIdx) {
      waypoints = path.sublist(fromIdx, toIdx + 1);
    } else {
      waypoints = [prevDisplayed, snap.snapped];
    }

    if (waypoints.length <= 1) {
      _displayedPositions[bus.id] = snap.snapped;
      notifyListeners();
      return;
    }

    _interpTimers[bus.id]?.cancel();
    int step = 0;
    // Animation duration 500ms (tuned)
    final ms = (500 / waypoints.length).round().clamp(20, 250);

    _interpTimers[bus.id] = Timer.periodic(Duration(milliseconds: ms), (timer) {
      if (step >= waypoints.length) {
        timer.cancel();
        return;
      }
      _displayedPositions[bus.id] = waypoints[step];
      step++;
      notifyListeners();
    });
  }

  bool _isBusInRestStop(Bus bus) {
    const distance = Distance();
    for (final stop in _restStops) {
      if (distance.as(LengthUnit.Meter, bus.position, stop) <=
          _restStopRadius) {
        return true;
      }
    }
    return false;
  }

  Future<List<LatLng>> _parseGeoJsonToPoints(String assetPath) async {
    String data = await rootBundle.loadString(assetPath);
    var jsonResult = jsonDecode(data);
    List<LatLng> points = [];

    var features = jsonResult['features'] as List;
    for (var feature in features) {
      var geometry = feature['geometry'];
      if (geometry['type'] == 'LineString') {
        var coordinates = geometry['coordinates'] as List;
        for (var coord in coordinates) {
          points.add(LatLng(coord[1], coord[0]));
        }
      }
    }
    return points;
  }

  // To prevent spamming notifications, we track the last alert time per bus
  final Map<String, DateTime> _lastOffRouteAlert = {};

  void _checkOffRouteStatus() {
    List<Map<String, dynamic>> offRouteBuses = [];

    for (var bus in _buses) {
      // 1. ถ้าอยู่ในจุดพักรถ -> ข้ามการเช็ค Off-route
      if (_isBusInRestStop(bus)) continue;

      // 2. หา Route Path ของรถคันนี้ (Dynamic & Config-aware)
      final path = _getRoutePathForBus(bus);

      if (path != null && path.isNotEmpty) {
        // 3. หาจุดที่ใกล้ที่สุดบนเส้นทาง
        final snap = _snapToRoute(bus.position, path);

        // 4. ตรวจสอบระยะเบี่ยงเบน
        if (snap.dist > _offRouteThresholdMeters) {
          offRouteBuses.add({'bus': bus, 'dist': snap.dist});

          // ALSO Show Local Notification (Alert) - FOR DRIVER (own bus only)
          // Driver alerts are still per-bus as it's their own bus
          if (_isCurrentUserDriver(bus.driverName)) {
            final lastAlert = _lastOffRouteAlert[bus.id];
            if (lastAlert == null ||
                DateTime.now().difference(lastAlert).inMinutes >= 1) {
              _lastOffRouteAlert[bus.id] = DateTime.now();
              NotificationService.showNotification(
                id: bus.id.hashCode + 1000,
                title: "⚠️ คุณออกนอกเส้นทาง!",
                body:
                    "รถ ${bus.name} เบี่ยงออกจากเส้นทาง ${snap.dist.toStringAsFixed(0)} เมตร กรุณากลับเข้าเส้นทาง",
                payload: "off_route_driver_${bus.id}",
              );
              NotificationService.vibrate();
            }
          }
        }
      }
    }

    // Handle aggregated Manager Notification
    if (_isCurrentUserManager()) {
      _handleManagerOffRouteNotification(offRouteBuses);
    }
  }

  void _handleManagerOffRouteNotification(
    List<Map<String, dynamic>> offRouteBuses,
  ) {
    if (offRouteBuses.isEmpty) {
      // Option: cancel notification if no more off-route buses
      // NotificationService.cancel(_aggregatedManagerAlertId);
      _lastOffRouteBusIds.clear();
      return;
    }

    final currentBusIds = offRouteBuses
        .map((e) => (e['bus'] as Bus).id)
        .toSet();
    final bool hasSetChanged = !setEquals(_lastOffRouteBusIds, currentBusIds);
    final bool isRateLimited =
        _lastAggregatedOffRouteAlert != null &&
        DateTime.now().difference(_lastAggregatedOffRouteAlert!).inMinutes < 1;

    // Only notify if the set of buses changed OR it's been > 1 minute
    if (!hasSetChanged && isRateLimited) return;

    _lastAggregatedOffRouteAlert = DateTime.now();
    _lastOffRouteBusIds = currentBusIds;

    String title;
    String body;

    if (offRouteBuses.length == 1) {
      final bus = offRouteBuses.first['bus'] as Bus;
      final dist = offRouteBuses.first['dist'] as double;
      title = "⚠️ แจ้งเตือนรถออกนอกเส้นทาง!";
      String driverInfo = bus.driverName.isNotEmpty
          ? " (คนขับ: ${bus.driverName})"
          : "";
      body =
          "รถ ${bus.name}$driverInfo (สาย ${bus.routeId}) เบี่ยงออกไป ${dist.toStringAsFixed(0)} เมตร";
    } else {
      title = "⚠️ แจ้งเตือนรถออกนอกเส้นทาง (${offRouteBuses.length} คัน)";
      final busNames = offRouteBuses
          .map((e) => (e['bus'] as Bus).name)
          .join(', ');
      body = "พบรถ ${offRouteBuses.length} คันมีปัญหา: $busNames";
    }

    NotificationService.showNotification(
      id: _aggregatedManagerAlertId,
      title: title,
      body: body,
      payload: "off_route_aggregation",
    );
    NotificationService.vibrate();

    // Log each bus to Firestore (keep existing logging logic)
    for (var item in offRouteBuses) {
      final bus = item['bus'] as Bus;
      final dist = item['dist'] as double;
      final lastAlert = _lastOffRouteAlert[bus.id];
      if (lastAlert == null ||
          DateTime.now().difference(lastAlert).inMinutes >= 1) {
        _lastOffRouteAlert[bus.id] = DateTime.now();
        try {
          FirebaseFirestore.instance.collection('off_route_logs').add({
            'bus_id': bus.id,
            'bus_name': bus.name,
            'driver_name': bus.driverName,
            'route_id': bus.routeId,
            'deviation_meters': dist,
            'timestamp': FieldValue.serverTimestamp(),
            'status': 'off-route',
            'location': {
              'lat': bus.position.latitude,
              'lng': bus.position.longitude,
            },
          });
        } catch (e) {
          debugPrint("❌ Failed to log off-route event: $e");
        }
      }
    }
  }

  bool _isCurrentUserManager() {
    final user = FirebaseAuth.instance.currentUser;
    // Hardcoded list from LoginPage (Ideally should be in a shared config)
    const managerEmails = ['admin@upbus.com', 'manager@upbus.com'];
    return user != null &&
        user.email != null &&
        managerEmails.contains(user.email);
  }

  /// เช็คว่า driverName ตรงกับชื่อคนขับที่ล็อกอินอยู่ (เก็บใน SharedPreferences)
  String? _cachedDriverName;
  bool _isCurrentUserDriver(String busDriverName) {
    if (busDriverName.isEmpty) return false;
    // ใช้ cached value ก่อน เพื่อไม่ต้อง await ทุกครั้ง
    if (_cachedDriverName != null) {
      return _cachedDriverName == busDriverName;
    }
    // โหลดจาก SharedPreferences แบบ fire-and-forget
    SharedPreferences.getInstance().then((prefs) {
      _cachedDriverName = prefs.getString('saved_driver_name');
    });
    return false; // ครั้งแรกยังไม่มี cache ให้ return false ก่อน
  }

  /// ปิด service (เรียกตอน dispose app)
  @override
  void dispose() {
    _busSubscription?.cancel();
    _positionSubscription?.cancel();
    _routeConfigSubscription?.cancel();
    super.dispose();
  }

  /// ตรวจสอบว่ารถบัสคันนี้ "ใช่" สายที่ต้องการหรือไม่ (Robust Matching)
  bool isBusMatchRoute(Bus bus, String target) {
    final t = target.trim().toLowerCase();
    final bId = bus.routeId.trim().toLowerCase();
    final bColor = bus.routeColor.trim().toLowerCase();

    // 1. Direct Matching
    if (bId.contains(t) || t.contains(bId)) return true;
    if (bColor.contains(t) || t.contains(bColor)) return true;

    // 2. Mapping S1 (Green)
    if (t.contains("s1") || t.contains("หน้ามอ")) {
      if (bId.contains("green") || bColor.contains("green")) return true;
      if (bColor.contains("เขียว")) return true;
    }

    // 3. Mapping S2 (Red)
    if (t.contains("s2") || t.contains("หอใน")) {
      if (bId.contains("red") || bColor.contains("red")) return true;
      if (bColor.contains("แดง")) return true;
    }

    // 4. Mapping S3 (Blue)
    if (t.contains("s3") || t.contains("ict")) {
      if (bId.contains("blue") || bColor.contains("blue")) return true;
      if (bColor.contains("น้ำเงิน")) return true;
    }

    return false;
  }
}

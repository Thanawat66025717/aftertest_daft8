import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// Import ไฟล์ของคุณเอง (ตรวจสอบ path ให้ถูกต้อง)
import 'package:projectapp/models/bus_model.dart';
import 'package:projectapp/models/bus_route_data.dart';
// route_service removed as it is now handled by GlobalLocationService
import 'package:projectapp/services/notification_service.dart';
import 'package:projectapp/services/global_location_service.dart';
import 'package:projectapp/services/route_manager_service.dart';
import 'package:projectapp/sidemenu.dart'; // import เมนูข้าง
import 'package:flutter_map_animations/flutter_map_animations.dart';

String? selectedBusStopId;

class UpBusHomePage extends StatefulWidget {
  const UpBusHomePage({super.key});

  @override
  State<UpBusHomePage> createState() => _UpBusHomePageState();
}

class _UpBusHomePageState extends State<UpBusHomePage> {
  int _selectedRouteIndex = 0;
  int _selectedBottomIndex = 0;

  // --- เพิ่มตัวแปรสำหรับ Interactive Marker ---
  String? _tappedBusId; // เก็บ ID ของรถที่ถูกกด

  final MapController _mapController = MapController();

  // Polylines are now generated dynamically in build() from routeManager.allRoutes
  // to support real-time updates without restarting the app.
  // redundant fields removed
  static const LatLng _kUniversity = LatLng(
    19.03011372185138,
    99.89781512200192,
  );

  // --- เพิ่มฟังก์ชันแปลงสีและชื่อสาย ---
  Color _getBusColor(String routeIdentifier) {
    try {
      final routeManager = Provider.of<RouteManagerService>(
        context,
        listen: false,
      );
      // Try to find route by color name or ID
      final route = routeManager.allRoutes.firstWhere(
        (r) =>
            r.routeId.toLowerCase() == routeIdentifier.toLowerCase() ||
            r.shortName.toLowerCase() == routeIdentifier.toLowerCase(),
      );
      return Color(route.colorValue);
    } catch (_) {}

    switch (routeIdentifier.toLowerCase()) {
      case 'green':
        return const Color(0xFF44B678);
      case 'red':
        return const Color(0xFFFF3859);
      case 'blue':
        return const Color(0xFF1177FC);
      default:
        return Colors.purple;
    }
  }

  // ฟังก์ชันเลือกไฟล์รูปไอคอนตามสีสายรถ
  String _getBusIconAsset(String routeIdentifier) {
    int? colorValue;
    try {
      final routeManager = Provider.of<RouteManagerService>(
        context,
        listen: false,
      );
      final route = routeManager.allRoutes.firstWhere(
        (r) =>
            r.routeId.toLowerCase() == routeIdentifier.toLowerCase() ||
            r.shortName.toLowerCase() == routeIdentifier.toLowerCase(),
      );
      colorValue = route.colorValue;
    } catch (_) {
      // Fallback matching by identifier name
      if (routeIdentifier.toLowerCase() == 'green') colorValue = 0xFF44B678;
      if (routeIdentifier.toLowerCase() == 'red') colorValue = 0xFFFF3859;
      if (routeIdentifier.toLowerCase() == 'blue') colorValue = 0xFF1177FC;
    }

    if (colorValue == 0xFF44B678) return 'assets/images/bus_green.png';
    if (colorValue == 0xFFFF3859) return 'assets/images/bus_red.png';
    if (colorValue == 0xFF1177FC) return 'assets/images/bus_blue.png';

    return 'assets/images/busiconall.png'; // Default purple bus
  }

  String _getRouteNameTh(String routeIdentifier) {
    try {
      final routeManager = Provider.of<RouteManagerService>(
        context,
        listen: false,
      );
      final route = routeManager.allRoutes.firstWhere(
        (r) =>
            r.routeId.toLowerCase() == routeIdentifier.toLowerCase() ||
            r.shortName.toLowerCase() == routeIdentifier.toLowerCase(),
      );
      return route.name;
    } catch (_) {}

    switch (routeIdentifier.toLowerCase()) {
      case 'green':
        return 'สายหน้ามอ (สีเขียว)';
      case 'red':
        return 'สายหอพัก (สีแดง)';
      case 'blue':
        return 'สายประตูสาม (สีน้ำเงิน)';
      default:
        return 'ไม่ระบุสาย';
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  // ... (ฟังก์ชันโหลดเส้นทาง _loadAllRoutes, _parseGeoJson, _filterRoutes คงเดิม) ...

  // (ใส่โค้ด _loadAllRoutes, _parseGeoJson, _filterRoutes เดิมของคุณตรงนี้)
  // List<Polyline> generation is now moved to build() for dynamic updates.
  List<Polyline> _generateDisplayPolylines(
    List<BusRouteData> dynamicRoutes,
    GlobalLocationService locationService,
  ) {
    List<Polyline> newDisplay = [];
    final isPKYActive = locationService.isGreenPKYActive();

    // 1. Generate all applicable polylines first
    List<Polyline> allPolylines = [];
    for (var route in dynamicRoutes) {
      if (route.pathPoints != null && route.pathPoints!.isNotEmpty) {
        List<LatLng> points = route.pathPoints!
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
        allPolylines.add(
          Polyline(
            points: points,
            color: Color(route.colorValue).withOpacity(1.0),
            strokeWidth: 4.0,
          ),
        );
      }
    }

    if (allPolylines.isEmpty) return [];

    // 2. Filter based on selected index
    if (_selectedRouteIndex == 0) {
      // All
      for (int i = 0; i < allPolylines.length; i++) {
        if (i < dynamicRoutes.length) {
          final route = dynamicRoutes[i];
          if (route.shortName == 'S1') {
            if (isPKYActive && route.routeId != 'S1-PM') continue;
            if (!isPKYActive && route.routeId != 'S1-AM') continue;
          }
        }
        newDisplay.add(allPolylines[i]);
      }
    } else {
      // Group unique routes to map index
      final uniqueRoutes = <BusRouteData>[];
      final seenShortNames = <String>{};
      for (var route in dynamicRoutes) {
        if (!seenShortNames.contains(route.shortName)) {
          seenShortNames.add(route.shortName);
          uniqueRoutes.add(route);
        }
      }

      if (_selectedRouteIndex <= uniqueRoutes.length) {
        final targetShortName = uniqueRoutes[_selectedRouteIndex - 1].shortName;
        for (int i = 0; i < dynamicRoutes.length; i++) {
          if (dynamicRoutes[i].shortName == targetShortName) {
            final route = dynamicRoutes[i];
            if (route.shortName == 'S1') {
              if (isPKYActive && route.routeId != 'S1-PM') continue;
              if (!isPKYActive && route.routeId != 'S1-AM') continue;
            }
            if (i < allPolylines.length) {
              newDisplay.add(allPolylines[i]);
            }
          }
        }
      }
    }
    return newDisplay;
  }

  Future<void> _initializeServices() async {
    await NotificationService.initialize();
    // Initialize GlobalLocationService here to ensure UI is ready for permission dialogs
    if (mounted) {
      context.read<GlobalLocationService>().initialize();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // _fetchBusStops removed

  @override
  Widget build(BuildContext context) {
    final locationService = context.watch<GlobalLocationService>();
    final routeManager = context.watch<RouteManagerService>();
    final dynamicRoutes = routeManager.allRoutes;
    final displayPolylines = _generateDisplayPolylines(
      dynamicRoutes,
      locationService,
    );
    final allBuses = locationService.buses;

    // Filter buses based on selected route index
    // [MODIFICATION] Handle grouped shortNames
    final uniqueRoutes = <BusRouteData>[];
    final seenShortNames = <String>{};
    for (var route in dynamicRoutes) {
      if (!seenShortNames.contains(route.shortName)) {
        seenShortNames.add(route.shortName);
        uniqueRoutes.add(route);
      }
    }

    final buses = allBuses.where((bus) {
      if (_selectedRouteIndex == 0) return true; // Show all

      if (_selectedRouteIndex <= uniqueRoutes.length) {
        final targetRoute = uniqueRoutes[_selectedRouteIndex - 1];
        return locationService.isBusMatchRoute(bus, targetRoute.shortName);
      }
      return true;
    }).toList();

    final notifyEnabled = locationService.notifyEnabled;

    return Scaffold(
      endDrawer: const SideMenu(), // ใช้งาน SideMenu ตรงนี้
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _kUniversity,
                                initialZoom: 16.5,
                                onTap: (_, __) {
                                  // แตะที่ว่างในแผนที่เพื่อปิด Popup
                                  if (_tappedBusId != null) {
                                    setState(() => _tappedBusId = null);
                                  }
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.upbus.app',
                                ),
                                PolylineLayer(polylines: displayPolylines),

                                // --- Bus Stop Markers ---
                                StreamBuilder(
                                  stream: FirebaseFirestore.instance
                                      .collection('bus_stops')
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData)
                                      return const MarkerLayer(markers: []);

                                    // 1. แปลงเป็น List ของ BusStopData
                                    final rawStops = snapshot.data!.docs
                                        .map(
                                          (doc) =>
                                              BusStopData.fromFirestore(doc),
                                        )
                                        .toList();

                                    // 2. ลบตัวซ้ำ (Deduplicate) โดยใช้ชื่อ
                                    // เนื่องจากอาจมีทั้งที่ Import จาก Default และที่พิกัดเพิ่มเอง
                                    final Map<String, BusStopData> stopMap = {};
                                    for (var s in rawStops) {
                                      bool isPlaceholder = s.isPlaceholder;

                                      if (!stopMap.containsKey(s.name)) {
                                        stopMap[s.name] = s;
                                      } else {
                                        // ถ้ามีชื่อซ้ำ ให้เลือกตัวที่ไม่ใช่พิกัดหลอก (ถ้ามี)
                                        bool existingIsPlaceholder =
                                            stopMap[s.name]?.isPlaceholder ??
                                            true;
                                        if (existingIsPlaceholder &&
                                            !isPlaceholder) {
                                          stopMap[s.name] = s;
                                        }
                                      }
                                    }
                                    List<BusStopData> deduplicatedStops =
                                        stopMap.values.toList();

                                    // 3. กรองตามสายที่เลือก (Filtering)
                                    final routeManager = context
                                        .read<RouteManagerService>();
                                    final isPKYActive = locationService
                                        .isGreenPKYActive();

                                    if (_selectedRouteIndex != 0) {
                                      // หา Route ที่เลือก
                                      final uniqueRoutes = <BusRouteData>[];
                                      final seenNames = <String>{};
                                      for (var r in routeManager.allRoutes) {
                                        if (!seenNames.contains(r.shortName)) {
                                          seenNames.add(r.shortName);
                                          uniqueRoutes.add(r);
                                        }
                                      }

                                      if (_selectedRouteIndex <=
                                          uniqueRoutes.length) {
                                        final targetShortName =
                                            uniqueRoutes[_selectedRouteIndex -
                                                    1]
                                                .shortName;

                                        // กรองเอาเฉพาะป้ายที่อยู่ในสายที่มี shortName นี้
                                        deduplicatedStops = deduplicatedStops.where((
                                          stop,
                                        ) {
                                          // เช็คว่าป้ายนี้อยู่ใน S1-AM, S1-PM, S2, หรือ S3 หรือไม่
                                          return routeManager.allRoutes.any((
                                            r,
                                          ) {
                                            if (r.shortName != targetShortName)
                                              return false;
                                            // ถ้าเป็น S1 ให้เช็ค PKY Active ด้วยเพื่อให้ป้ายตรงกับจุดจอดจริงตามเวลา
                                            if (r.shortName == 'S1') {
                                              if (isPKYActive &&
                                                  r.routeId != 'S1-PM')
                                                return false;
                                              if (!isPKYActive &&
                                                  r.routeId != 'S1-AM')
                                                return false;
                                            }
                                            return r.hasStop(stop.id) ||
                                                r.stops.any(
                                                  (rs) => rs.name == stop.name,
                                                );
                                          });
                                        }).toList();
                                      }
                                    }

                                    return MarkerLayer(
                                      markers: deduplicatedStops.map((stop) {
                                        final lat =
                                            stop.location?.latitude ?? 0.0;
                                        final lng =
                                            stop.location?.longitude ?? 0.0;

                                        return Marker(
                                          point: LatLng(lat, lng),
                                          width: 200,
                                          height: 100,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                selectedBusStopId =
                                                    (selectedBusStopId ==
                                                        stop.id)
                                                    ? null
                                                    : stop.id;
                                              });
                                            },
                                            child: Stack(
                                              alignment: Alignment.bottomCenter,
                                              children: [
                                                if (selectedBusStopId ==
                                                    stop.id)
                                                  Positioned(
                                                    top: 0,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        boxShadow: const [
                                                          BoxShadow(
                                                            color:
                                                                Colors.black26,
                                                            blurRadius: 4,
                                                            offset: Offset(
                                                              0,
                                                              2,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      child: Text(
                                                        stop.name,
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 10,
                                                      ),
                                                  child: Image.asset(
                                                    'assets/images/bus-stopicon.png',
                                                    width: 60,
                                                    height: 60,
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),

                                // --- Live Bus Markers (แบบใช้รูปแยกสี) ---
                                AnimatedMarkerLayer(
                                  markers: buses.map((bus) {
                                    final isSelected = _tappedBusId == bus.id;
                                    final routeNameTh = _getRouteNameTh(
                                      bus.routeColor,
                                    );
                                    final busIconAsset = _getBusIconAsset(
                                      bus.routeColor,
                                    );
                                    final borderColor = _getBusColor(
                                      bus.routeColor,
                                    );

                                    // 1. เปลี่ยนจาก Marker เป็น AnimatedMarker
                                    return AnimatedMarker(
                                      key: ValueKey(bus.id),
                                      point: bus.position,
                                      width: 140,
                                      height: 140,
                                      // 2. ย้าย duration และ curve มาไว้ตรงนี้
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.linear,

                                      // 3. AnimatedMarker ใช้ 'builder' แทน 'child'
                                      builder: (context, animation) {
                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _tappedBusId = isSelected
                                                  ? null
                                                  : bus.id;
                                            });
                                          },
                                          child: Stack(
                                            alignment: Alignment.bottomCenter,
                                            clipBehavior: Clip.none,
                                            children: [
                                              // --- Popup แสดงข้อมูล ---
                                              if (isSelected)
                                                Positioned(
                                                  bottom: 80,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      boxShadow: const [
                                                        BoxShadow(
                                                          color: Colors.black26,
                                                          blurRadius: 8,
                                                          offset: Offset(0, 4),
                                                        ),
                                                      ],
                                                      border: Border.all(
                                                        color: borderColor,
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          bus
                                                                  .driverName
                                                                  .isNotEmpty
                                                              ? "คนขับ: ${bus.driverName}"
                                                              : "คนขับ: ไม่ระบุ",
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13,
                                                                color: Colors
                                                                    .black87,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          bus.name,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .grey[700],
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        Text(
                                                          routeNameTh,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: borderColor,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        if (bus.distanceToUser !=
                                                            null) ...[
                                                          Text(
                                                            "ห่าง ${bus.distanceToUser!.toStringAsFixed(0)} ม.",
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .black87,
                                                                ),
                                                          ),
                                                          Builder(
                                                            builder: (context) {
                                                              final dist = bus
                                                                  .distanceToUser!;
                                                              // Speed 30 km/h = ~8.33 m/s
                                                              // Speed 50 km/h = ~13.88 m/s
                                                              final maxSeconds =
                                                                  (dist / 8.33)
                                                                      .ceil();
                                                              final minSeconds =
                                                                  (dist / 13.88)
                                                                      .ceil();

                                                              String timeText;
                                                              if (maxSeconds <
                                                                  60) {
                                                                if (minSeconds ==
                                                                    maxSeconds) {
                                                                  timeText =
                                                                      "ประมาณ $minSeconds วินาที";
                                                                } else {
                                                                  timeText =
                                                                      "ประมาณ $minSeconds-$maxSeconds วินาที";
                                                                }
                                                              } else {
                                                                final maxMinutes =
                                                                    (maxSeconds /
                                                                            60)
                                                                        .ceil();
                                                                final minMinutes =
                                                                    (minSeconds /
                                                                            60)
                                                                        .ceil();

                                                                if (minMinutes ==
                                                                    maxMinutes) {
                                                                  timeText =
                                                                      "ประมาณ $minMinutes นาที";
                                                                } else {
                                                                  timeText =
                                                                      "ประมาณ $minMinutes-$maxMinutes นาที";
                                                                }
                                                              }

                                                              return Text(
                                                                timeText,
                                                                style: const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .black87,
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ),

                                              // --- ไอคอนรถ ---
                                              Positioned(
                                                bottom: 40,
                                                child: Image.asset(
                                                  busIconAsset,
                                                  width: 50,
                                                  height: 50,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  }).toList(),
                                ),

                                // --- User Location Marker ---
                                // --- User Location Marker (แก้ใหม่ให้หายแดง) ---
                                if (locationService.userPosition != null)
                                  AnimatedMarkerLayer(
                                    markers: [
                                      AnimatedMarker(
                                        key: const ValueKey('user_location'),
                                        point: locationService.userPosition!,
                                        width: 50,
                                        height: 50,
                                        duration: const Duration(
                                          milliseconds: 1000,
                                        ),
                                        builder: (context, animation) => Stack(
                                          alignment: Alignment.bottomCenter,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withOpacity(
                                                  0.2,
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.blue
                                                      .withOpacity(0.5),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                color: Colors.blue,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 3,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.blue
                                                        .withOpacity(0.4),
                                                    blurRadius: 8,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),

                            // ปุ่มลอยด้านขวา (Notification / My Location)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Column(
                                children: [
                                  _floatingMapIcon(
                                    icon: notifyEnabled
                                        ? Icons.notifications_active
                                        : Icons.notifications_none,
                                    onTap: _onNotificationIconTap,
                                  ),
                                  const SizedBox(height: 12),
                                  _floatingMapIcon(
                                    icon: Icons.my_location,
                                    onTap: _goToMyLocation,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (notifyEnabled) _buildProximityAlertBox(locationService),

                  // === Debug Bar แสดงป้ายที่ใกล้ที่สุด ===
                  Consumer<GlobalLocationService>(
                    builder: (context, locationService, child) {
                      final hasPosition = locationService.userPosition != null;
                      return GestureDetector(
                        onTap: () {
                          // ไปหน้า Bus Stop พร้อมส่งข้อมูลป้ายที่ใกล้ที่สุด
                          final closestStop = locationService.findClosestStop();
                          if (closestStop != null) {
                            Navigator.pushNamed(
                              context,
                              '/busStopMap',
                              arguments: {
                                'id': closestStop['id'],
                                'name': closestStop['name'],
                                'lat': closestStop['lat'],
                                'long': closestStop['long'],
                                'routeId': closestStop['route_id'],
                              },
                            );
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: hasPosition
                                  ? [
                                      const Color.fromARGB(255, 12, 93, 214),
                                      const Color.fromARGB(255, 0, 172, 224),
                                    ]
                                  : [
                                      Colors.grey.shade600,
                                      Colors.grey.shade400,
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              // ไอคอนแสดงสถานะ GPS
                              Icon(
                                hasPosition ? Icons.gps_fixed : Icons.gps_off,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              // ข้อมูลหลัก
                              Expanded(
                                child: Text(
                                  hasPosition
                                      ? '📍 ${locationService.getClosestStopInfo()}'
                                      : '🔍 กำลังหาตำแหน่ง...',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // ลูกศรชี้ไปหน้า busstop
                              const Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.white,
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // === END Debug Bar ===
                  Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _routeButton(
                            label: 'ภาพรวม',
                            color: const Color.fromRGBO(143, 55, 203, 1),
                            isSelected: _selectedRouteIndex == 0,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 0);
                            },
                          ),
                        ),
                        ...uniqueRoutes.asMap().entries.map((entry) {
                          int idx = entry.key + 1; // 1, 2, 3...
                          var route = entry.value;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6.0),
                              child: _routeButton(
                                label: route.shortName,
                                color: route.colorValue == 0xFF000000
                                    ? Colors.grey
                                    : Color(
                                        route.colorValue,
                                      ).withValues(alpha: 1.0),
                                isSelected: _selectedRouteIndex == idx,
                                onPressed: () {
                                  setState(() => _selectedRouteIndex = idx);
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Widget ย่อยๆ (คงเดิม) ---

  Widget _routeButton({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : Colors.white,
        foregroundColor: isSelected ? Colors.white : color,
        side: BorderSide(color: color, width: 2),
        minimumSize: const Size(double.infinity, 30),
        padding: const EdgeInsets.symmetric(vertical: 14),
        elevation: isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF9C27B0),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Text(
            'LIVE MAP',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),

          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingMapIcon({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
    Color iconColor = Colors.blue,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 28,
        ), // Adjust icon size slightly
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    final locationService = context.read<GlobalLocationService>();
    if (locationService.userPosition != null) {
      _mapController.move(locationService.userPosition!, 17);
    }
  }

  Future<void> _onNotificationIconTap() async {
    await _showRouteSelectionDialog();
  }

  Future<void> _showRouteSelectionDialog() async {
    final globalService = context.read<GlobalLocationService>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Color(0xFF9C27B0)),
            SizedBox(width: 8),
            Text('เลือกสายที่จะแจ้งเตือน'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            _routeSelectionTile(
              title: 'รถทุกสาย',
              subtitle: 'แจ้งเตือนเมื่อรถสายใดก็ได้เข้าใกล้',
              color: const Color(0xFF9C27B0),
              icon: Icons.all_inclusive,
              isSelected:
                  globalService.notifyEnabled &&
                  globalService.selectedNotifyRouteId == null &&
                  globalService.destinationName == null,
              onTap: () {
                globalService.setDestination(null, null); // Clear destination
                globalService.setNotifyEnabled(
                  true,
                  routeId: null,
                ); // Use null for "All Routes"
                Navigator.pop(dialogContext);
                _showNotificationSnackBar('ทุกสาย');
              },
            ),
            const Divider(),
            ...(() {
              final routeManager = context.read<RouteManagerService>();
              final uniqueRoutes = <BusRouteData>[];
              final seenNames = <String>{};
              for (var r in routeManager.allRoutes) {
                if (!seenNames.contains(r.shortName)) {
                  seenNames.add(r.shortName);
                  uniqueRoutes.add(r);
                }
              }
              return uniqueRoutes.map(
                (route) => _routeSelectionTile(
                  title:
                      '${route.shortName} ${route.name.replaceAll(RegExp(r'\(.*\)'), '').trim()}',
                  subtitle: 'แจ้งเตือนเฉพาะสาย ${route.shortName}',
                  color: Color(route.colorValue),
                  icon: Icons.directions_bus,
                  isSelected:
                      globalService.notifyEnabled &&
                      globalService.selectedNotifyRouteId !=
                          null && // Ensure not null
                      globalService.selectedNotifyRouteId!.toLowerCase() ==
                          route.shortName.toLowerCase() &&
                      globalService.destinationName == null,
                  onTap: () {
                    globalService.setDestination(null, null);
                    globalService.setNotifyEnabled(
                      true,
                      routeId: route.shortName, // Pass shortName (e.g., "S1")
                    );
                    Navigator.pop(dialogContext);
                    _showNotificationSnackBar(
                      '${route.shortName} ${route.name.replaceAll(RegExp(r'\(.*\)'), '').trim()}',
                    );
                  },
                ),
              );
            })(),
          ],
        ),
        actions: [
          if (globalService.notifyEnabled)
            TextButton.icon(
              onPressed: () {
                globalService.setDestination(null, null); // ล้างค่าปลายทางด้วย
                globalService.setNotifyEnabled(false);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔕 ปิดการแจ้งเตือนและยกเลิกปลายทาง'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.grey,
                  ),
                );
              },
              icon: const Icon(Icons.notifications_off, color: Colors.red),
              label: const Text(
                'ปิดการแจ้งเตือน',
                style: TextStyle(color: Colors.red),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
  }

  Widget _routeSelectionTile({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.green)
          : null,
      onTap: onTap,
      selected: isSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  void _showNotificationSnackBar(String routeName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔔 เปิดการแจ้งเตือน: $routeName (ระยะ 250 เมตร)'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildProximityAlertBox(GlobalLocationService locationService) {
    final selectedNotifyRouteId = locationService.selectedNotifyRouteId;
    final targetBus = locationService.targetBus;

    // 2. กรณีไม่ได้เลือกปลายทาง (หรือเลือกปลายทางแต่ยังไม่เจอรถ) - และยังไม่เจอรถ
    if (targetBus == null) {
      final routeInfo = selectedNotifyRouteId != null
          ? BusRoute.fromId(selectedNotifyRouteId)
          : null;

      final isSearchingLocation = locationService.userPosition == null;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey, width: 2),
        ),
        child: Row(
          children: [
            isSearchingLocation
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.grey,
                    ),
                  )
                : Icon(Icons.search, color: Colors.grey.shade600, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔔 กำลังติดตาม: ${routeInfo?.name.replaceAll(RegExp(r'\(.*\)'), '').trim() ?? "ทุกสาย"}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    isSearchingLocation
                        ? 'กำลังระบุตำแหน่งของคุณ...'
                        : 'ยังไม่พบรถที่กำลังมาถึง...',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 3. กรณีไม่ได้เลือกปลายทาง - เจอรถแล้ว (แสดงผลปกติแบบเดิม)
    Color routeColor = Colors.orange;
    String? routeShortName;
    try {
      final routeManager = Provider.of<RouteManagerService>(
        context,
        listen: false,
      );
      final bus = targetBus;

      // หาข้อมูลสายจาก RouteManager หรือ BusRoute legacy
      final routeInfo = routeManager.allRoutes.cast<dynamic>().firstWhere(
        (r) =>
            r.routeId.toLowerCase() == bus.routeId.toLowerCase() ||
            r.shortName.toLowerCase() == bus.routeId.toLowerCase() ||
            r.shortName.toLowerCase() == bus.routeColor.toLowerCase(),
        orElse: () => null,
      );

      if (routeInfo != null) {
        routeColor = Color(routeInfo.colorValue);
        routeShortName = routeInfo.shortName;
      } else {
        // Fallback legacy matching
        final rId = bus.routeId.toLowerCase();
        final rColor = bus.routeColor.toLowerCase();
        if (rId.contains('s1') ||
            rColor.contains('green') ||
            rColor.contains('เขียว')) {
          routeColor = const Color(0xFF44B678);
          routeShortName = 'S1';
        } else if (rId.contains('s2') ||
            rColor.contains('red') ||
            rColor.contains('แดง')) {
          routeColor = const Color(0xFFFF3859);
          routeShortName = 'S2';
        } else if (rId.contains('s3') ||
            rColor.contains('blue') ||
            rColor.contains('น้ำเงิน')) {
          routeColor = const Color(0xFF1177FC);
          routeShortName = 'S3';
        }
      }
    } catch (_) {}
    final isNear =
        (targetBus.distanceToUser ?? double.infinity) <=
        500; // Assuming 500 meters for "near"

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNear ? Colors.orange.shade100 : routeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNear ? Colors.orange : routeColor,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_bus,
            color: isNear ? Colors.orange : routeColor,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔔 ${selectedNotifyRouteId != null ? "ติดตาม ${routeShortName ?? selectedNotifyRouteId}" : "ติดตามทุกสาย"}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  '🚌 ${targetBus.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'ระยะห่าง: ${targetBus.distanceToUser?.toStringAsFixed(0) ?? "N/A"} เมตร',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                if (targetBus.distanceToUser != null)
                  Text(
                    'เวลาประมาณการ: ${NotificationService.formatEta(NotificationService.calculateEtaSeconds(targetBus.distanceToUser!))}',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          if (isNear)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'ใกล้แล้ว!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF9C27B0),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: SizedBox(
        height: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bottomNavItem(0, Icons.location_on, 'Live'),
            _bottomNavItem(1, Icons.directions_bus, 'Stop'),
            _bottomNavItem(2, Icons.map, 'Route'),
            _bottomNavItem(3, Icons.alt_route, 'Plan'),
            _bottomNavItem(4, Icons.feedback, 'Feed'),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedBottomIndex == index;
    return InkWell(
      onTap: () {
        if (index == _selectedBottomIndex) return;
        switch (index) {
          case 0:
            break;
          case 1:
            Navigator.pushReplacementNamed(context, '/busStop');
            break;
          case 2:
            Navigator.pushReplacementNamed(context, '/route');
            break;
          case 3:
            Navigator.pushReplacementNamed(context, '/plan');
            break;
          case 4:
            Navigator.pushReplacementNamed(context, '/feedback');
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: isSelected ? 28 : 24),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

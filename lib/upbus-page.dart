import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
// firebase_database removed
import 'package:cloud_firestore/cloud_firestore.dart';
// geolocator removed as it is now handled by GlobalLocationService
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

// Import ไฟล์ของคุณเอง (ตรวจสอบ path ให้ถูกต้อง)
import 'models/bus_model.dart';
// route_service removed as it is now handled by GlobalLocationService
import 'services/notification_service.dart';
import 'services/global_location_service.dart';
import 'sidemenu.dart'; // import เมนูข้าง
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

  List<Polyline> _allPolylines = [];
  List<Polyline> _displayPolylines = [];
  Polyline? _routeNamorPKY;
  // redundant fields removed
  static const LatLng _kUniversity = LatLng(
    19.03011372185138,
    99.89781512200192,
  );

  // --- เพิ่มฟังก์ชันแปลงสีและชื่อสาย ---
  Color _getBusColor(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'green':
        return const Color.fromRGBO(68, 182, 120, 1);
      case 'red':
        return const Color.fromRGBO(255, 56, 89, 1);
      case 'blue':
        return const Color.fromRGBO(17, 119, 252, 1);
      default:
        return Colors.purple;
    }
  }

  // ฟังก์ชันเลือกไฟล์รูปไอคอนตามสีสายรถ
  String _getBusIconAsset(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'green':
        return 'assets/images/bus_green.png';
      case 'red':
        return 'assets/images/bus_red.png';
      case 'blue':
        return 'assets/images/bus_blue.png';
      default:
        return 'assets/images/busiconall.png'; // สี default หรือสีอื่นๆ
    }
  }

  String _getRouteNameTh(String colorName) {
    switch (colorName.toLowerCase()) {
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
    _loadAllRoutes();
  }

  // ... (ฟังก์ชันโหลดเส้นทาง _loadAllRoutes, _parseGeoJson, _filterRoutes คงเดิม) ...

  // (ใส่โค้ด _loadAllRoutes, _parseGeoJson, _filterRoutes เดิมของคุณตรงนี้)
  /// โหลดเส้นทางรถบัสทั้ง 3 สายจากไฟล์ GeoJSON แล้วแปลงเป็น Polyline สำหรับแสดงบนแผนที่
  /// - สายหน้ามอ (เขียว): โหลด 2 เส้นทาง (ช่วงเช้า bus_route1_pm2 / ช่วงบ่าย bus_route1)
  /// - สายหอพัก (แดง): โหลดจาก bus_route2
  /// - สายประตูงาม/ICT (น้ำเงิน): โหลดจาก bus_route3
  /// หลังโหลดเสร็จจะเก็บไว้ใน _allPolylines และแสดงทั้งหมดเป็นค่าเริ่มต้น
  Future<void> _loadAllRoutes() async {
    try {
      Polyline routeNamor = await _parseGeoJson(
        'assets/data/bus_route1_pm2.geojson',
        const Color.fromRGBO(68, 182, 120, 1),
      );
      _routeNamorPKY = await _parseGeoJson(
        'assets/data/bus_route1.geojson',
        const Color.fromRGBO(68, 182, 120, 1),
      );
      Polyline routeHornai = await _parseGeoJson(
        'assets/data/bus_route2.geojson',
        const Color.fromRGBO(255, 56, 89, 1),
      );
      Polyline routeICT = await _parseGeoJson(
        'assets/data/bus_route3.geojson',
        const Color.fromRGBO(17, 119, 252, 1),
      );

      if (!mounted) return;
      setState(() {
        _allPolylines = [routeNamor, routeHornai, routeICT];
        _displayPolylines = _allPolylines;
      });
    } catch (e) {
      debugPrint("Error loading routes: $e");
    }
  }

  /// อ่านไฟล์ GeoJSON จาก assets แล้วแปลงพิกัด (coordinates) เป็น Polyline
  /// - [assetPath]: path ของไฟล์ GeoJSON ใน assets เช่น 'assets/data/bus_route1.geojson'
  /// - [color]: สีของเส้น Polyline ที่จะวาดบนแผนที่
  /// ขั้นตอน: อ่านไฟล์ → decode JSON → วนลูปดึง coordinates จาก features ที่เป็น LineString
  ///         → แปลงเป็น List<LatLng> → สร้าง Polyline พร้อมสีและความหนา 4.0
  Future<Polyline> _parseGeoJson(String assetPath, Color color) async {
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
    return Polyline(points: points, color: color, strokeWidth: 4.0);
  }

  /// กรองเส้นทางที่จะแสดงบนแผนที่ตาม index ของปุ่มที่ผู้ใช้เลือก
  /// ใช้ isGreenPKYActive() จาก GlobalLocationService แทน hardcode เวลา
  void _filterRoutes(int index, GlobalLocationService locationService) {
    if (_allPolylines.isEmpty) return;
    setState(() {
      // ถ้า Manager ตั้งค่า PKY mode → ใช้เส้น PKY; ไม่งั้นใช้เส้นปกติ
      final isPKYActive = locationService.isGreenPKYActive();
      final currentNamor = isPKYActive
          ? (_routeNamorPKY ?? _allPolylines[0])
          : _allPolylines[0];

      if (index == 0) {
        _displayPolylines = [currentNamor, _allPolylines[1], _allPolylines[2]];
      } else if (index == 1) {
        _displayPolylines = [currentNamor];
      } else if (index == 2) {
        _displayPolylines = [_allPolylines[1]];
      } else if (index == 3) {
        _displayPolylines = [_allPolylines[2]];
      }
    });
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
    final allBuses = locationService.buses;

    // Filter buses based on selected route index
    final buses = allBuses.where((bus) {
      if (_selectedRouteIndex == 0) return true; // Show all
      if (_selectedRouteIndex == 1)
        return bus.routeColor.toLowerCase() == 'green';
      if (_selectedRouteIndex == 2)
        return bus.routeColor.toLowerCase() == 'red';
      if (_selectedRouteIndex == 3)
        return bus.routeColor.toLowerCase() == 'blue';
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
                                PolylineLayer(polylines: _displayPolylines),

                                // --- Destination Flag Marker (ธงปักจุดหมาย) ---
                                if (locationService.destinationPosition != null)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: locationService
                                            .destinationPosition!,
                                        width: 10,
                                        height: 35,
                                        alignment: Alignment.topCenter,
                                        child: const Icon(
                                          Icons.flag,
                                          color: Color.fromARGB(
                                            255,
                                            2,
                                            173,
                                            31,
                                          ),
                                          size: 30,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 10,
                                              color: Colors.black45,
                                              offset: Offset(2, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                // --- Bus Stop Markers (คงเดิม) ---
                                StreamBuilder(
                                  stream: FirebaseFirestore.instance
                                      .collection('Bus stop')
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData)
                                      return const MarkerLayer(markers: []);
                                    return MarkerLayer(
                                      markers: snapshot.data!.docs.map((doc) {
                                        var data = doc.data();
                                        return Marker(
                                          point: LatLng(
                                            double.parse(
                                              data['lat'].toString(),
                                            ),
                                            double.parse(
                                              data['long'].toString(),
                                            ),
                                          ),
                                          width: 200,
                                          height: 100,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                selectedBusStopId =
                                                    (selectedBusStopId ==
                                                        doc.id)
                                                    ? null
                                                    : doc.id;
                                              });
                                            },
                                            child: Stack(
                                              alignment: Alignment.bottomCenter,
                                              children: [
                                                if (selectedBusStopId == doc.id)
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
                                                        data['name'].toString(),
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
                                            alignment: Alignment.center,
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
                                          alignment: Alignment.center,
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
                              _filterRoutes(
                                0,
                                context.read<GlobalLocationService>(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _routeButton(
                            label: 'หน้ามอ',
                            color: const Color.fromRGBO(68, 182, 120, 1),
                            isSelected: _selectedRouteIndex == 1,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 1);
                              _filterRoutes(
                                1,
                                context.read<GlobalLocationService>(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _routeButton(
                            label: 'หอใน',
                            color: const Color.fromRGBO(255, 56, 89, 1),
                            isSelected: _selectedRouteIndex == 2,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 2);
                              _filterRoutes(
                                2,
                                context.read<GlobalLocationService>(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _routeButton(
                            label: 'ICT',
                            color: const Color.fromRGBO(17, 119, 252, 1),
                            isSelected: _selectedRouteIndex == 3,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 3);
                              _filterRoutes(
                                3,
                                context.read<GlobalLocationService>(),
                              );
                            },
                          ),
                        ),
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
              color: Colors.black.withOpacity(0.2),
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

  Future<void> _showDestinationSelectionDialog() async {
    final globalService = context.read<GlobalLocationService>();
    final stops = globalService.allBusStops;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.flag, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('เลือกปลายทาง'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: stops.isEmpty
              ? const Center(child: Text("ไม่พบข้อมูลป้าย"))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: stops.length,
                  itemBuilder: (context, index) {
                    final stop = stops[index];
                    final routeId = stop['route_id']?.toString() ?? 'Unknown';
                    // แปลง route_id เป็นสีเพื่อแสดงผล
                    Color routeColor = Colors.grey;
                    if (routeId.toLowerCase().contains('green'))
                      routeColor = Colors.green;
                    else if (routeId.toLowerCase().contains('red'))
                      routeColor = Colors.red;
                    else if (routeId.toLowerCase().contains('blue'))
                      routeColor = Colors.blue;

                    final isSelected =
                        globalService.destinationName == stop['name'];

                    return ListTile(
                      leading: Icon(Icons.place, color: routeColor),
                      title: Text(stop['name']),
                      subtitle: Text("สาย: $routeId"),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: () {
                        // ตั้งค่า destination
                        globalService.setDestination(stop['name'], routeId);
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("📍 กำหนดปลายทาง: ${stop['name']}"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        actions: [
          if (globalService.destinationName != null)
            TextButton(
              onPressed: () {
                globalService.setDestination(null, null);
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'ยกเลิกปลาทาง',
                style: TextStyle(color: Colors.red),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ปิด'),
          ),
        ],
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
            _routeSelectionTile(
              title: 'ระบุปลายทาง (Destination)',
              subtitle: globalService.destinationName != null
                  ? 'กำลังไป: ${globalService.destinationName}'
                  : 'เลือกป้ายที่คุณจะลง เพื่อแจ้งเตือนเฉพาะรถสายที่ผ่าน',
              color: Colors.redAccent,
              icon: Icons.flag,
              isSelected: globalService.destinationName != null,
              onTap: () {
                Navigator.pop(dialogContext);
                _showDestinationSelectionDialog();
              },
            ),
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
                globalService.setNotifyEnabled(true, routeId: null);
                Navigator.pop(dialogContext);
                _showNotificationSnackBar('ทุกสาย');
              },
            ),
            const Divider(),
            ...BusRoute.allRoutes.map(
              (route) => _routeSelectionTile(
                title: '${route.id} ${route.name}',
                subtitle: 'แจ้งเตือนเฉพาะสาย ${route.shortName}',
                color: Color(route.colorValue),
                icon: Icons.directions_bus,
                isSelected:
                    globalService.notifyEnabled &&
                    globalService.selectedNotifyRouteId == route.id &&
                    globalService.destinationName == null,
                onTap: () {
                  globalService.setDestination(
                    null,
                    null,
                  ); // ล้างค่าปลายทางถ้าเลือกเป็นสาย
                  globalService.setNotifyEnabled(true, routeId: route.id);
                  Navigator.pop(dialogContext);
                  _showNotificationSnackBar('${route.id} ${route.name}');
                },
              ),
            ),
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
    final buses = locationService.buses;
    final selectedNotifyRouteId = locationService.selectedNotifyRouteId;

    Bus? targetBus;
    if (selectedNotifyRouteId == null) {
      targetBus = locationService.closestBus;
    } else {
      final targetId = selectedNotifyRouteId.trim().toLowerCase();
      final filtered = buses.where((b) {
        final busRouteId = b.routeId.trim().toLowerCase();
        return busRouteId.contains(targetId) || targetId.contains(busRouteId);
      }).toList();
      if (filtered.isNotEmpty) {
        filtered.sort(
          (a, b) => (a.distanceToUser ?? double.infinity).compareTo(
            b.distanceToUser ?? double.infinity,
          ),
        );
        targetBus = filtered.first;
      }
    }

    // 1. กรณีเลือกปลายทาง (Destination) - แสดงแบบพิเศษ
    if (locationService.destinationName != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue, width: 2),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.blue, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "ปลายทาง: ${locationService.destinationName}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            if (targetBus != null) ...[
              Row(
                children: [
                  const Icon(Icons.directions_bus, color: Colors.black54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "รถสาย ${targetBus.routeId} กำลังมา (${targetBus.name})",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'อีก ${targetBus.distanceToUser?.toStringAsFixed(0) ?? "?"} ม. (${NotificationService.formatEta(NotificationService.calculateEtaSeconds(targetBus.distanceToUser ?? 0))})',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  "กำลังรอรถสายที่ผ่าน...",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      );
    }

    // 2. กรณีไม่ได้เลือกปลายทาง - และยังไม่เจอรถ
    if (targetBus == null) {
      final routeInfo = selectedNotifyRouteId != null
          ? BusRoute.fromId(selectedNotifyRouteId)
          : null;
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
            Icon(Icons.search, color: Colors.grey.shade600, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔔 กำลังติดตาม: ${routeInfo?.name ?? "ทุกสาย"}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'ยังไม่พบรถในสายนี้',
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
    final routeInfo = BusRoute.fromId(targetBus.routeId);
    final routeColor = routeInfo != null
        ? Color(routeInfo.colorValue)
        : Colors.orange;
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
                  '🔔 ${selectedNotifyRouteId != null ? "ติดตาม ${routeInfo?.shortName ?? selectedNotifyRouteId}" : "ติดตามทุกสาย"}',
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

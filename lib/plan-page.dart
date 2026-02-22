import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:projectapp/upbus-page.dart';
import 'services/route_planner_service.dart';
import 'services/route_manager_service.dart';
import 'models/bus_route_data.dart';
import 'sidemenu.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  int _selectedBottomIndex = 3;

  String? _selectedSourceId;
  String? _selectedDestinationId;
  String? _selectedSourceName;
  String? _selectedDestinationName;

  // --- ตัวแปรสำหรับ OSM ---
  final MapController _mapController = MapController();
  List<Polyline> _polylines = [];
  List<Marker> _markers = [];

  // ผลลัพธ์การหาเส้นทาง (หลายตัวเลือก)
  List<RouteResult> _routeResults = [];
  int _selectedRouteIndex = 0; // index ของ route ที่เลือก
  bool _isRoutesExpanded = true;
  bool _isSearchExpanded = true; // State for collapsible input

  // เก็บ GeoJSON segments แบบละเอียด (Start -> End)
  final List<Map<String, dynamic>> _detailedRouteSegments = [];

  // --- Cached Bus Stops ---
  List<DropdownMenuItem<String>> _busStopItems = [];
  Map<String, String> _stopIdToName = {};
  bool _isLoadingStops = true;

  // พิกัดเริ่มต้น (ม.พะเยา)
  static const LatLng _kUniversity = LatLng(
    19.03011372185138,
    99.89781512200192,
  );

  @override
  void initState() {
    super.initState();
    _loadRouteGeoJson();
    _loadBusStops(); // Load stops once
  }

  Future<void> _loadBusStops() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bus_stops')
          .get();

      final List<DropdownMenuItem<String>> items = [];
      final Map<String, String> idMap = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'].toString();

        idMap[doc.id] = name;
        items.add(
          DropdownMenuItem(
            value: doc.id,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
        );
      }

      // Optional: Sort by name
      items.sort((a, b) {
        final nameA = (a.child as Text).data ?? "";
        final nameB = (b.child as Text).data ?? "";
        return nameA.compareTo(nameB);
      });

      if (mounted) {
        setState(() {
          _busStopItems = items;
          _stopIdToName = idMap;
          _isLoadingStops = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading bus stops: $e");
      if (mounted) {
        setState(() {
          _isLoadingStops = false;
        });
      }
    }
  }

  Future<void> _loadRouteGeoJson() async {
    try {
      // โหลด polyline ย่อยๆ เพื่อให้เส้นทางวาดสวยขึ้น
      await _loadDetailedRoutePlan();
    } catch (e) {
      debugPrint('Error loading GeoJSON: $e');
    }
  }

  Future<void> _loadDetailedRoutePlan() async {
    try {
      String data = await rootBundle.loadString(
        'assets/data/route_plan.geojson',
      );
      var jsonResult = jsonDecode(data);
      var features = jsonResult['features'] as List;

      for (var feature in features) {
        var props = feature['properties'];
        var geometry = feature['geometry'];
        String routeName = props['route_name'] ?? ''; // e.g., "A – B"

        if (geometry['type'] == 'LineString' && routeName.isNotEmpty) {
          var coordinates = geometry['coordinates'] as List;
          List<LatLng> points = [];
          for (var coord in coordinates) {
            points.add(LatLng(coord[1], coord[0]));
          }

          // แยกชื่อต้นทาง - ปลายทาง
          // สมมติ format: "สถานีหน้าโรงเรียนสาธิตมหาวิทยาลัยพะเยา – สถานีหน้าอาคารสงวนเสริมศรี"
          var parts = routeName.split('–').map((e) => e.trim()).toList();
          if (parts.length == 2) {
            _detailedRouteSegments.add({
              'from': parts[0],
              'to': parts[1],
              'points': points,
            });
          }
        }
      }
      debugPrint('Loaded ${_detailedRouteSegments.length} detailed segments.');
    } catch (e) {
      debugPrint('Error loading route_plan.geojson: $e');
    }
  }

  /// อ่านไฟล์ GeoJSON จาก assets
  Future<Polyline> _parseGeoJson(String assetPath, Color color) async {
    try {
      String data = await rootBundle.loadString(assetPath);
      var jsonResult = jsonDecode(data);
      var features = jsonResult['features'] as List;
      List<LatLng> points = [];

      for (var feature in features) {
        var geometry = feature['geometry'];
        if (geometry['type'] == 'LineString') {
          var coordinates = geometry['coordinates'] as List;
          for (var coord in coordinates) {
            points.add(LatLng(coord[1], coord[0]));
          }
        }
      }

      return Polyline(points: points, strokeWidth: 4.0, color: color);
    } catch (e) {
      debugPrint("Error parsing GeoJSON: $e");
      return Polyline(points: [], color: color);
    }
  }

  // Helper สำหรับค้นหาเส้นทางย่อยที่ตรงกับชื่อป้าย
  List<LatLng>? _findMatchingSegmentPoints(
    String fromStopName,
    String toStopName,
  ) {
    // ลองค้นหาแบบ Fuzzy match
    for (var seg in _detailedRouteSegments) {
      String segFrom = seg['from'];
      String segTo = seg['to'];

      // Simple contain check
      if (segFrom.contains(fromStopName) && segTo.contains(toStopName)) {
        return seg['points'] as List<LatLng>;
      }
      // ลองสลับ name check (เผื่อชื่อใน json ยาวกว่าหรือสั้นกว่า)
      if (fromStopName.contains(segFrom) && toStopName.contains(segTo)) {
        return seg['points'] as List<LatLng>;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: const SideMenu(),
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),

            // --- ส่วน Input (เลือกต้นทาง/ปลายทาง) ---
            AnimatedCrossFade(
              firstChild: _buildFullSearchInput(),
              secondChild: _buildCompactSearchHeader(),
              crossFadeState: _isSearchExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 300),
            ),

            // --- ส่วนแสดงผลลัพธ์เส้นทาง ---
            if (_routeResults.isNotEmpty) _buildRouteResultCards(),

            // --- ส่วนแสดงแผนที่ OSM ---
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _kUniversity,
                      initialZoom: 14.5,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.upbus.upbus',
                      ),
                      PolylineLayer(polylines: _polylines),
                      StreamBuilder(
                        stream: FirebaseFirestore.instance
                            .collection('bus_stops')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const MarkerLayer(markers: []);
                          }
                          return MarkerLayer(
                            markers: snapshot.data!.docs.map((doc) {
                              final stop = BusStopData.fromFirestore(doc);
                              final lat = stop.location?.latitude ?? 0.0;
                              final lng = stop.location?.longitude ?? 0.0;

                              return Marker(
                                point: LatLng(lat, lng),
                                width: 200,
                                height: 100,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      selectedBusStopId =
                                          (selectedBusStopId == doc.id)
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
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 4,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              stop.name,
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.only(
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
                      MarkerLayer(markers: _markers),
                    ],
                  ),
                ],
              ),
            ),

            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // --- ฟังก์ชันหาเส้นทางรถบัส ---
  Future<void> _onSearchBusRoute() async {
    if (_selectedSourceId == null || _selectedDestinationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกต้นทางและปลายทาง')),
      );
      return;
    }

    // แปลง Firebase ID เป็น internal stop ID
    final fromStopId = RoutePlannerService.mapFirebaseIdToStopId(
      _selectedSourceId!,
      _selectedSourceName ?? '',
    );
    final toStopId = RoutePlannerService.mapFirebaseIdToStopId(
      _selectedDestinationId!,
      _selectedDestinationName ?? '',
    );

    debugPrint('Searching Route:');
    debugPrint(
      'Source Input: $_selectedSourceName (ID: $_selectedSourceId) -> Mapped: $fromStopId',
    );
    debugPrint(
      'Dest Input: $_selectedDestinationName (ID: $_selectedDestinationId) -> Mapped: $toStopId',
    );

    if (fromStopId == null || toStopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถระบุป้ายได้ กรุณาลองใหม่')),
      );
      return;
    }

    // หาเส้นทางทั้งหมด
    final expectedRoutes = context.read<RouteManagerService>().allRoutes;
    final results = RoutePlannerService.findAllRoutes(
      fromStopId,
      toStopId,
      expectedRoutes,
    );

    setState(() {
      _routeResults = results;
      _selectedRouteIndex = 0; // Reset index to avoid out of range error
      _polylines.clear();
      _markers.clear();
    });

    if (results.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ไม่พบเส้นทาง')));
      return;
    }

    // วาดเส้นทางแรก (ที่ดีที่สุด)
    await _drawBusRoute(results.first);

    // เพิ่มหมุดต้นทาง/ปลายทาง
    await _addRouteMarkers();

    // Collapse search panel to show map
    setState(() {
      _isSearchExpanded = false;
    });
  }

  Future<void> _drawBusRoute(RouteResult result) async {
    final List<Polyline> newPolylines = [];
    final List<LatLng> allPoints = [];

    for (final segment in result.segments) {
      // พยายามหาเส้นทางแบบละเอียด (Specific Segment)
      final specificPoints = _findMatchingSegmentPoints(
        segment.fromStop.name,
        segment.toStop.name,
      );

      if (specificPoints != null && specificPoints.isNotEmpty) {
        // เจอเส้นทางละเอียด -> ใช้อันนี้
        newPolylines.add(
          Polyline(
            points: specificPoints,
            strokeWidth: 6.0, // เส้นหนาขึ้นนิดหน่อยเพื่อให้เห็นชัด
            color: Color(segment.route.colorValue),
          ),
        );
        allPoints.addAll(specificPoints);
      } else {
        // ไม่เจอ -> ใช้เส้นทางทั้งสายจาก Firestore (Fallback)
        final points = segment.route.pathPoints
            ?.map((p) => LatLng(p.latitude, p.longitude))
            .toList();
        if (points != null && points.isNotEmpty) {
          newPolylines.add(
            Polyline(
              points: points,
              strokeWidth: 5.0,
              color: Color(
                segment.route.colorValue,
              ).withValues(alpha: 0.6), // จางลงนิดหน่อย
            ),
          );
          allPoints.addAll(points);
        }
      }
    }

    if (newPolylines.isEmpty) {
      // Fallback: ใช้เส้นทางสายหลักจาก GeoJSON ถ้าไม่พบเส้นทางละเอียด
      for (final segment in result.segments) {
        String assetPath = '';
        if (segment.route.routeId == 'S1-PM') {
          assetPath = 'assets/data/bus_route1_pm.geojson';
        } else if (segment.route.routeId == 'S1-AM' ||
            segment.route.routeId == 'S1') {
          assetPath = 'assets/data/bus_route1_am.geojson';
        } else if (segment.route.routeId.contains('S2')) {
          assetPath = 'assets/data/bus_route2.geojson';
        } else if (segment.route.routeId.contains('S3')) {
          assetPath = 'assets/data/bus_route3.geojson';
        }

        if (assetPath.isNotEmpty) {
          final color = Color(segment.route.colorValue);
          final fallbackPoly = await _parseGeoJson(assetPath, color);
          if (fallbackPoly.points.isNotEmpty) {
            newPolylines.add(fallbackPoly);
            allPoints.addAll(fallbackPoly.points);
          }
        }
      }
    }

    if (newPolylines.isEmpty) {
      // Fallback 2: ใช้เส้นตรงถ้าไม่พบทั้ง GeoJSON
      final startCoords = await _getCoordsFromFirebase(_selectedSourceId!);
      final endCoords = await _getCoordsFromFirebase(_selectedDestinationId!);
      if (startCoords != null && endCoords != null) {
        newPolylines.add(
          Polyline(
            points: [startCoords, endCoords],
            strokeWidth: 4.0,
            color: Colors.purple,
          ),
        );
        allPoints.addAll([startCoords, endCoords]);
      }
    }

    setState(() {
      _polylines = newPolylines;
    });

    // ซูมให้เห็นเส้นทางทั้งหมด
    if (allPoints.isNotEmpty) {
      LatLngBounds bounds = LatLngBounds.fromPoints(allPoints);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
      );
    }
  }

  Future<void> _addRouteMarkers() async {
    if (_routeResults.isEmpty) return;

    final result = _routeResults[_selectedRouteIndex];
    final List<Marker> routeMarkers = [];
    int stopNumber = 1;

    for (int segIdx = 0; segIdx < result.segments.length; segIdx++) {
      final segment = result.segments[segIdx];
      final color = Color(segment.route.colorValue);
      final isFirstSegment = segIdx == 0;
      final isLastSegment = segIdx == result.segments.length - 1;

      // === Start point (เฉพาะ segment แรก) ===
      if (isFirstSegment) {
        final startCoords = await _getStopCoords(segment.fromStop.id);
        if (startCoords != null) {
          routeMarkers.add(
            _createRouteStopMarker(
              point: startCoords,
              label: 'เริ่ม',
              stopName: segment.fromStop.shortName ?? segment.fromStop.name,
              color: color,
              isStart: true,
              isEnd: false,
              isTransfer: false,
            ),
          );
        }
        stopNumber++;
      }

      // === Intermediate stops ===
      for (final stop in segment.stopsInBetween) {
        final coords = await _getStopCoords(stop.id);
        if (coords != null) {
          routeMarkers.add(
            _createRouteStopMarker(
              point: coords,
              label: '$stopNumber',
              stopName: stop.shortName ?? stop.name,
              color: color,
              isStart: false,
              isEnd: false,
              isTransfer: false,
            ),
          );
        }
        stopNumber++;
      }

      // === End point or Transfer point ===
      final endCoords = await _getStopCoords(segment.toStop.id);
      if (endCoords != null) {
        if (isLastSegment) {
          // Final destination
          routeMarkers.add(
            _createRouteStopMarker(
              point: endCoords,
              label: 'ถึง',
              stopName: segment.toStop.shortName ?? segment.toStop.name,
              color: Colors.green,
              isStart: false,
              isEnd: true,
              isTransfer: false,
            ),
          );
        } else {
          // Transfer point
          final nextColor = Color(result.segments[segIdx + 1].route.colorValue);
          routeMarkers.add(
            _createRouteStopMarker(
              point: endCoords,
              label: 'เปลี่ยน',
              stopName: segment.toStop.shortName ?? segment.toStop.name,
              color: color,
              nextColor: nextColor,
              isStart: false,
              isEnd: false,
              isTransfer: true,
            ),
          );
        }
        stopNumber++;
      }
    }

    setState(() {
      _markers = routeMarkers;
    });
  }

  /// สร้าง Marker สำหรับป้ายบนเส้นทาง
  Marker _createRouteStopMarker({
    required LatLng point,
    required String label,
    required String stopName,
    required Color color,
    Color? nextColor,
    required bool isStart,
    required bool isEnd,
    required bool isTransfer,
  }) {
    return Marker(
      point: point,
      width: isStart ? 100 : 80,
      height: isStart ? 90 : 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isEnd
                  ? Colors.green
                  : (isTransfer ? Colors.orange : color),
              borderRadius: BorderRadius.circular(isStart ? 12 : 8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              stopName,
              style: TextStyle(
                color: Colors.white,
                fontSize: isStart ? 11 : 9,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          // Circle marker
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnd ? Colors.green : (isStart ? color : Colors.white),
              // Start point larger border
              border: Border.all(
                color: isTransfer ? (nextColor ?? color) : color,
                width: isStart ? 4 : 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: isStart
                  ? Icon(
                      Icons.my_location,
                      color: Colors.white,
                      size: 14,
                    ) // Changed icon
                  : (isEnd
                        ? Icon(Icons.flag, color: Colors.white, size: 12)
                        : (isTransfer
                              ? Icon(Icons.swap_horiz, color: color, size: 14)
                              : null)),
            ),
          ),
        ],
      ),
    );
  }

  /// ดึง coordinates จาก stop ID
  Future<LatLng?> _getStopCoords(String stopId) async {
    // ลองหาจาก Firebase โดยใช้ชื่อ
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bus_stops')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.toLowerCase() ?? '';

        // Match by stop ID
        if (_matchesStopId(name, stopId)) {
          final stop = BusStopData.fromFirestore(doc);
          return LatLng(
            stop.location?.latitude ?? 0.0,
            stop.location?.longitude ?? 0.0,
          );
        }
      }
    } catch (e) {
      debugPrint("Error fetching stop coords: $e");
    }
    return null;
  }

  bool _matchesStopId(String name, String stopId) {
    final nameLower = name.toLowerCase();
    switch (stopId) {
      case 'pky':
        return nameLower.contains('pky') || nameLower.contains('พีเค');
      case 'namor':
        return nameLower.contains('หน้ามอ') ||
            nameLower.contains('ม.พะเยา') ||
            nameLower.contains('หน้ามหาวิทยาลัย');
      case 'engineering':
        return nameLower.contains('วิศว');
      case 'auditorium':
        return nameLower.contains('ประชุม') || nameLower.contains('พญางำเมือง');
      case 'president':
        return nameLower.contains('อธิการ');
      case 'arts':
        return nameLower.contains('ศิลป');
      case 'science':
        return nameLower.contains('วิทยาศาสตร์') ||
            nameLower.contains('science') ||
            nameLower.contains('เภสัช');
      case 'gate3':
        return nameLower.contains('ประตู') && nameLower.contains('3') ||
            nameLower.contains('หลังมอ');
      case 'economy_center':
        return nameLower.contains('เศรษฐกิจ');
      case 'ict':
        return nameLower.contains('ict') ||
            nameLower.contains('เทคโนโลยีสารสนเทศ');
      case 'ub99':
        return nameLower.contains('99') || nameLower.contains('ub');
      case 'wiangphayao':
        return nameLower.contains('เวียง');
      case 'sanguansermsri':
        return nameLower.contains('สงวน');
      case 'satit':
        return nameLower.contains('สาธิต');
      default:
        return false;
    }
  }

  Future<LatLng?> _getCoordsFromFirebase(String docId) async {
    try {
      var doc = await FirebaseFirestore.instance
          .collection('bus_stops')
          .doc(docId)
          .get();
      if (doc.exists) {
        final stop = BusStopData.fromFirestore(doc);
        return LatLng(
          stop.location?.latitude ?? 0.0,
          stop.location?.longitude ?? 0.0,
        );
      }
    } catch (e) {
      debugPrint("Error fetching coords: $e");
    }
    return null;
  }

  // --- Widget แสดงผลลัพธ์เส้นทางทั้งหมด ---
  Widget _buildRouteResultCards() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: _isRoutesExpanded ? 180 : 60, // ปรับความสูงตามสถานะ
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isRoutesExpanded = !_isRoutesExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.alt_route, color: Colors.purple, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "แนะนำ ${_routeResults.length} เส้นทาง",
                      style: TextStyle(
                        color: Colors.purple.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isRoutesExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.purple,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isRoutesExpanded)
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: _routeResults.length,
                  itemBuilder: (context, index) {
                    final result = _routeResults[index];
                    final isFirst = index == 0;
                    return _buildSingleRouteCard(result, isFirst, index);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleRouteCard(
    RouteResult result,
    bool isRecommended,
    int optionIndex,
  ) {
    final isSelected = optionIndex == _selectedRouteIndex;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: Colors.purple.shade400, width: 2)
            : Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: () async {
          setState(() {
            _selectedRouteIndex = optionIndex;
          });
          await _drawBusRoute(result);
          await _addRouteMarkers();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // หัวข้อ
            Row(
              children: [
                Text(
                  'ตัวเลือก ${optionIndex + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                // [NEW] Recommended Badge for first option
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.thumb_up,
                          color: Colors.white,
                          size: 10,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'แนะนำ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                const Spacer(),
                if (result.transferCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'เปลี่ยน ${result.transferCount}',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Horizontal Layout: Timeline + TimeNote (Right)
            // Horizontal Layout: Timeline only (Full width)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: _buildRouteTimeline(result))],
            ),

            // 2. Time Note (Moved below timeline)
            if (result.timeNote != null && result.timeNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: result.timeNote!.toString().contains('⛔')
                      ? Colors.red.shade50
                      : (result.timeNote!.toString().contains('✅')
                            ? Colors.green.shade50
                            : Colors.orange.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: result.timeNote!.toString().contains('⛔')
                        ? Colors.red.shade200
                        : (result.timeNote!.toString().contains('✅')
                              ? Colors.green.shade200
                              : Colors.orange.shade200),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      result.timeNote!.toString().contains('⛔')
                          ? '⛔'
                          : (result.timeNote!.toString().contains('✅')
                                ? '✅'
                                : '⚠️'),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.timeNote!
                            .replaceAll('⛔ ', '')
                            .replaceAll('✅ ', '')
                            .replaceAll('⚠️ ', ''),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: result.timeNote!.toString().contains('⛔')
                              ? Colors.red.shade800
                              : (result.timeNote!.toString().contains('✅')
                                    ? Colors.green.shade800
                                    : Colors.orange.shade900),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 3. Summary (Moved below timeline)
            if (result.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "สรุป",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            result.message,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// สร้าง Visual Timeline แนวนอน
  /// สร้าง Visual Timeline แนวตั้ง (Vertical)
  Widget _buildRouteTimeline(RouteResult result) {
    final List<Widget> nodes = [];

    for (int i = 0; i < result.segments.length; i++) {
      final segment = result.segments[i];
      final isFirst = i == 0;
      final isLast = i == result.segments.length - 1;
      final color = Color(segment.route.colorValue);

      // === Start Point (เฉพาะ segment แรก) ===
      if (isFirst) {
        nodes.add(
          _buildTimelineNode(
            label: 'เริ่มต้น',
            stopName: segment.fromStop.shortName ?? segment.fromStop.name,
            color: color,
            isStart: true,
            isEnd: false,
          ),
        );
      }

      // === Line + Route Badge ===
      nodes.add(
        _buildTimelineLine(
          color: color,
          routeName: segment.route.shortName,
          stopCount: segment.stopCount,
        ),
      );

      // === Transfer Point หรือ End Point ===
      if (isLast) {
        nodes.add(
          _buildTimelineNode(
            label: 'จุดหมาย',
            stopName: segment.toStop.shortName ?? segment.toStop.name,
            color: color,
            isStart: false,
            isEnd: true,
          ),
        );
      } else {
        // Transfer point
        final nextColor = Color(result.segments[i + 1].route.colorValue);
        nodes.add(
          _buildTimelineNode(
            label: 'จุดเปลี่ยน',
            stopName: segment.toStop.shortName ?? segment.toStop.name,
            color: color,
            nextColor: nextColor,
            isStart: false,
            isEnd: false,
          ),
        );
      }
    }

    return Stack(
      children: [
        // The Scrollable List
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 24), // Add padding for icon
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: nodes,
          ),
        ),

        // Visual Indicator (Arrow) if likely to overflow
        if (result.segments.length > 2)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withOpacity(0.0),
                    Colors.white.withOpacity(0.8),
                    Colors.white,
                  ],
                ),
              ),
              padding: const EdgeInsets.only(left: 16, right: 0),
              child: Center(
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineNode({
    required String label,
    required String stopName,
    required Color color,
    Color? nextColor,
    required bool isStart,
    required bool isEnd,
  }) {
    Color borderColor;
    Color backgroundColor;
    Widget? icon;
    Color labelColor;

    if (isStart) {
      borderColor = color; // Use route color
      backgroundColor = color; // Use route color
      icon = const Icon(Icons.gps_fixed, color: Colors.white, size: 16);
      labelColor = color; // Use route color
    } else if (isEnd) {
      borderColor = Colors.green;
      backgroundColor = Colors.green;
      icon = const Icon(Icons.flag, color: Colors.white, size: 14);
      labelColor = Colors.green.shade800;
    } else {
      borderColor = nextColor ?? color;
      backgroundColor = Colors.white;
      icon = Icon(Icons.swap_horiz, color: nextColor ?? color, size: 14);
      labelColor = Colors.grey.shade600;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: isStart ? 32 : (isEnd ? 32 : 24),
          height: isStart ? 32 : (isEnd ? 32 : 24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor,
            border: Border.all(
              color: borderColor,
              width: isStart || isEnd ? 0 : 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(child: icon),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: Text(
            stopName,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineLine({
    required Color color,
    required String routeName,
    required int stopCount,
  }) {
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(height: 4, width: double.infinity, color: color),
              Positioned(
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    routeName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "$stopCount ป้าย",
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // --- Widgets UI ---
  Widget _buildDropdown(
    String label,
    IconData icon,
    Color color,
    String? val,
    Function(String?, String?) onChange, {
    String? excludeId,
  }) {
    if (_isLoadingStops) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text("กำลังโหลดข้อมูลป้าย..."),
          ],
        ),
      );
    }

    // Filter items based on excludeId
    final displayItems = excludeId == null
        ? _busStopItems
        : _busStopItems.where((item) => item.value != excludeId).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: val,
          isExpanded: true,
          items: displayItems,
          onChanged: (newVal) {
            if (newVal != null) {
              onChange(newVal, _stopIdToName[newVal]);
            }
          },
          hint: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0),
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
            'PLANNER',
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

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0),
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
            Navigator.pushReplacementNamed(context, '/');
            break;
          case 1:
            Navigator.pushReplacementNamed(context, '/busStop');
            break;
          case 2:
            Navigator.pushReplacementNamed(context, '/route');
            break;
          case 3:
            break;
          case 4:
            Navigator.pushReplacementNamed(context, '/feedback');
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  // --- New Helper Widgets for Collapsible Search ---

  Widget _buildFullSearchInput() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 12,
      ), // Increased horizontal padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildDropdown(
            "ต้นทาง (Start)",
            Icons.my_location,
            Colors.blue,
            _selectedSourceId,
            (val, name) {
              setState(() {
                _selectedSourceId = val;
                _selectedSourceName = name;
              });
            },
            excludeId: _selectedDestinationId, // Exclude selected destination
          ),
          Container(
            height: 12,
            padding: const EdgeInsets.only(left: 23),
            alignment: Alignment.centerLeft,
            child: Container(width: 2, color: Colors.grey.shade300),
          ),
          _buildDropdown(
            "ปลายทาง (Destination)",
            Icons.location_on,
            Colors.red,
            _selectedDestinationId,
            (val, name) {
              setState(() {
                _selectedDestinationId = val;
                _selectedDestinationName = name;
              });
            },
            excludeId: _selectedSourceId, // Exclude selected source
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _onSearchBusRoute,
              icon: const Icon(Icons.directions_bus),
              label: const Text("แสดงเส้นทางรถบัส"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCE6BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSearchHeader() {
    return InkWell(
      onTap: () {
        setState(() {
          _isSearchExpanded = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(15),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.my_location, color: Colors.blue, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedSourceName ?? 'เลือกต้นทาง',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, color: Colors.grey, size: 18),
            ),
            Icon(Icons.location_on, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedDestinationName ?? 'เลือกปลายทาง',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit, size: 18, color: Colors.purple),
            ),
          ],
        ),
      ),
    );
  }
}

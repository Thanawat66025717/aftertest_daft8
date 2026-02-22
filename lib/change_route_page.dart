import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'services/route_manager_service.dart';
import 'services/global_location_service.dart';
import 'models/bus_route_data.dart';
import 'upbus-page.dart';

class ChangeRoutePage extends StatefulWidget {
  const ChangeRoutePage({super.key});

  @override
  State<ChangeRoutePage> createState() => _ChangeRoutePageState();
}

class _ChangeRoutePageState extends State<ChangeRoutePage>
    with TickerProviderStateMixin {
  // ─── Tab Controller ──────────────────────────────────────────────────────
  late TabController _tabController;

  // ─── Driver State ────────────────────────────────────────────────────────
  String? _driverName;
  String? _selectedBus;
  String? _selectedRoute;
  Map<String, String> _busStatus = {};
  Map<String, String> _todaySchedule = {};
  bool _isLoadingSchedule = true;

  final List<String> _allBusIds = List.generate(30, (i) => "bus_${i + 1}");

  // ─── Map State ───────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  List<LatLng> _routePolyline = [];
  LatLng? _myBusPosition;
  bool _isOffRoute = false;
  String _offRouteMessage = '';
  StreamSubscription? _myBusSubscription;

  // ─── History State ───────────────────────────────────────────────────────
  int _historyDays = 7;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _checkSavedDriverName();
    _listenToBusStatusRealtime();
    _fetchTodaySchedule();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _myBusSubscription?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── EXISTING LOGIC (เดิม) ─────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _checkSavedDriverName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedName = prefs.getString('saved_driver_name');
    if (savedName != null && savedName.isNotEmpty) {
      setState(() => _driverName = savedName);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDriverNameDialog();
      });
    }
  }

  Future<void> _fetchTodaySchedule() async {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month}-${now.day}";
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bus_schedule')
          .doc(dateStr)
          .get();
      if (mounted) {
        setState(() {
          _isLoadingSchedule = false;
          if (snapshot.exists && snapshot.data() != null) {
            _todaySchedule.clear();
            snapshot.data()!.forEach((key, value) {
              if (key.startsWith('bus_')) {
                _todaySchedule[key] = value.toString();
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching schedule: $e");
      if (mounted) setState(() => _isLoadingSchedule = false);
    }
  }

  Future<void> _showDriverNameDialog() async {
    if (!mounted) return;
    final TextEditingController nameController = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Row(
              children: [
                Icon(Icons.badge, color: Colors.purple),
                SizedBox(width: 10),
                Text("ระบุตัวตน"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("กรุณากรอกชื่อของคุณเพื่อเริ่มงาน"),
                const SizedBox(height: 15),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: "ชื่อคนขับ / ชื่อเล่น",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "ยกเลิก",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                onPressed: () async {
                  if (nameController.text.trim().isNotEmpty) {
                    String name = nameController.text.trim();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('saved_driver_name', name);
                    setState(() => _driverName = name);
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  "ยืนยัน",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _listenToBusStatusRealtime() {
    FirebaseDatabase.instance.ref("GPS").onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      Map<String, String> newStatus = {};
      Map<String, String> busColors = {};

      if (data is Map) {
        data.forEach((key, value) {
          String dName = "";
          String dColor = "";
          if (value is Map && value.containsKey('driverName')) {
            dName = value['driverName'].toString();
            if (value.containsKey('routeColor'))
              dColor = value['routeColor'].toString();
          } else if (value is Map &&
              value.containsKey(key) &&
              value[key] is Map) {
            var inner = value[key];
            if (inner.containsKey('driverName')) {
              dName = inner['driverName'].toString();
              if (inner.containsKey('routeColor'))
                dColor = inner['routeColor'].toString();
            }
          }
          if (dName.isNotEmpty) {
            newStatus[key.toString()] = dName;
            if (dColor.isNotEmpty) busColors[key.toString()] = dColor;
          }
        });
      }

      setState(() {
        _busStatus = newStatus;
        if (_driverName != null) {
          final myBusEntry = newStatus.entries.firstWhere(
            (e) => e.value == _driverName,
            orElse: () => const MapEntry("", ""),
          );
          if (myBusEntry.key.isNotEmpty) {
            if (_selectedBus == null) _selectedBus = myBusEntry.key;
            if (_selectedBus == myBusEntry.key && _selectedRoute == null) {
              String? savedColor = busColors[myBusEntry.key];
              if (savedColor != null && savedColor.isNotEmpty) {
                _selectedRoute = savedColor;
              }
            }
          }
        }
      });
    });
  }

  void _submitData() async {
    if (_selectedBus == null || _selectedRoute == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("กรุณาเลือกข้อมูลให้ครบ")));
      return;
    }
    String? currentDriver = _busStatus[_selectedBus];
    if (currentDriver != null &&
        currentDriver.isNotEmpty &&
        currentDriver != _driverName) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("❌ เลือกไม่ได้ครับ"),
          content: Text(
            "รถคันนี้มีคนขับชื่อ '$currentDriver' ใช้งานอยู่\nกรุณาเลือกคันอื่น หรือแจ้งให้เขากด 'เลิกงาน' ก่อน",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ตกลง"),
            ),
          ],
        ),
      );
      return;
    }
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );
      DatabaseReference refSimple = FirebaseDatabase.instance.ref(
        "GPS/$_selectedBus",
      );
      String colorName = _getRouteColorName(_selectedRoute);
      Map<String, dynamic> updateData = {
        "driverName": _driverName,
        "routeColor": colorName,
        "routeName": _getRouteName(_selectedRoute!),
        "lastUpdate": ServerValue.timestamp,
      };
      await refSimple.update(updateData);
      try {
        final now = DateTime.now();
        await FirebaseFirestore.instance.collection('bus_operation_logs').add({
          "bus_id": _selectedBus,
          "driver_name": _driverName,
          "route_id": _selectedRoute, // บันทึก ID เส้นทาง (เช่น S1-AM, S2)
          "route_color": colorName,
          "route_name": _getRouteName(_selectedRoute!),
          "timestamp": FieldValue.serverTimestamp(),
          "year": now.year,
          "month": now.month,
          "day": now.day,
        });
      } catch (logErr) {
        debugPrint("Error logging bus operation: $logErr");
      }
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const UpBusHomePage()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ บันทึก: $_driverName ขับ $_selectedBus"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Error: $e");
    }
  }

  void _releaseBus() async {
    if (_selectedBus == null) return;
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("พักเบรค / เลิกงาน?"),
            content: Text(
              "คุณต้องการเลิกขับรถ $_selectedBus ใช่หรือไม่?\nสถานะรถจะเปลี่ยนเป็น 'ว่าง'",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("ยกเลิก"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "ยืนยัน",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );
      DatabaseReference refSimple = FirebaseDatabase.instance.ref(
        "GPS/$_selectedBus",
      );
      await refSimple.update({
        "driverName": "",
        "routeColor": "white",
        "routeName": "ว่าง",
        "lastUpdate": ServerValue.timestamp,
      });
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const UpBusHomePage()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🛑 พักรถเรียบร้อย"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Error releasing: $e");
    }
  }

  String _getRouteName(String valueOrId) {
    if (!mounted) return "";
    final rs = context.read<RouteManagerService>();
    var route = rs.allRoutes.firstWhere(
      (r) =>
          r.routeId == valueOrId ||
          r.shortName.toLowerCase() == valueOrId ||
          (r.colorValue.toString() == valueOrId),
      orElse: () => BusRouteData(
        routeId: valueOrId,
        name: valueOrId,
        shortName: '',
        colorValue: 0xffffff,
        stops: [],
      ),
    );
    return route.name;
  }

  String _formatBusName(String busId) {
    return "รถเบอร์ ${busId.split('_').last}";
  }

  /// แปลงค่า _selectedRoute (ที่อาจเป็น 'green','red','blue' จาก schedule)
  /// ให้ตรงกับ routeId ใน DropdownMenuItem ('S1-AM','S2','S3' ฯลฯ)
  String? _resolveRouteDropdownValue(List<BusRouteData> dynamicRoutes) {
    if (_selectedRoute == null) return null;
    // เช็คว่ามี item ที่ value ตรงกันอยู่แล้วหรือเปล่า
    final exactMatch = dynamicRoutes.any((r) => r.routeId == _selectedRoute);
    if (exactMatch) return _selectedRoute;

    // ถ้าไม่ตรง — ลอง map จากชื่อสี legacy เป็น routeId
    final c = _selectedRoute!.toLowerCase();
    String? mapped;
    if (c.contains('green') || c == 's1') {
      // เลือก S1-AM หรือ S1-PM ตามเวลา
      final locService = GlobalLocationService();
      mapped = locService.isGreenPKYActive() ? 'S1-PM' : 'S1-AM';
    } else if (c.contains('red') || c == 's2') {
      mapped = 'S2';
    } else if (c.contains('blue') || c == 's3' || c.contains('ict')) {
      mapped = 'S3';
    }

    // เช็คว่า mapped value อยู่ใน items จริงไหม
    if (mapped != null && dynamicRoutes.any((r) => r.routeId == mapped)) {
      return mapped;
    }
    return null; // ถ้าไม่เจอเลย ให้แสดง hint แทน
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── MAP HELPERS (ฟีเจอร์ 1 + 2) ──────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  /// โหลด polyline จาก GeoJSON asset
  Future<List<LatLng>> _parseGeoJson(String assetPath) async {
    try {
      String data = await rootBundle.loadString(assetPath);
      var json = jsonDecode(data);
      List<LatLng> points = [];
      var features = json['features'] as List;
      for (var feature in features) {
        var geometry = feature['geometry'];
        if (geometry['type'] == 'LineString') {
          var coords = geometry['coordinates'] as List;
          for (var c in coords) {
            points.add(LatLng(c[1], c[0]));
          }
        }
      }
      return points;
    } catch (e) {
      debugPrint("Error parsing GeoJSON: $e");
      return [];
    }
  }

  /// หา GeoJSON asset ที่ตรงกับ routeColor
  Future<void> _loadRoutePolyline(String? routeColor) async {
    if (routeColor == null) return;
    final c = routeColor.toLowerCase();
    String? asset;
    if (c.contains('green') || c.contains('s1')) {
      // เช็ค PKY config
      final locService = GlobalLocationService();
      if (locService.isGreenPKYActive()) {
        asset = 'assets/data/bus_route1_pm.geojson';
      } else {
        asset = 'assets/data/bus_route1_am.geojson';
      }
    } else if (c.contains('red') || c.contains('s2')) {
      asset = 'assets/data/bus_route2.geojson';
    } else if (c.contains('blue') || c.contains('s3') || c.contains('ict')) {
      asset = 'assets/data/bus_route3.geojson';
    }
    if (asset != null) {
      final points = await _parseGeoJson(asset);
      if (mounted) setState(() => _routePolyline = points);
    }
  }

  /// เริ่ม listen ตำแหน่งรถของเรา
  void _startListeningMyBus(String busId) {
    _myBusSubscription?.cancel();
    _loadRoutePolyline(_selectedRoute);

    _myBusSubscription = FirebaseDatabase.instance
        .ref("GPS/$busId")
        .onValue
        .listen((event) {
          if (!mounted) return;
          final data = event.snapshot.value;
          if (data is Map) {
            final lat = data['lat'];
            final lng = data['lng'];
            if (lat != null && lng != null) {
              final pos = LatLng(
                double.parse(lat.toString()),
                double.parse(lng.toString()),
              );
              // เช็ค off-route
              bool offRoute = false;
              String offMsg = '';
              if (_routePolyline.isNotEmpty) {
                const dist = Distance();
                double minDist = double.infinity;
                for (var pt in _routePolyline) {
                  final d = dist.as(LengthUnit.Meter, pos, pt);
                  if (d < minDist) minDist = d;
                }
                if (minDist > 50.0) {
                  offRoute = true;
                  offMsg =
                      "⚠️ ออกนอกเส้นทาง ${minDist.toStringAsFixed(0)} เมตร!";
                }
              }
              setState(() {
                _myBusPosition = pos;
                _isOffRoute = offRoute;
                _offRouteMessage = offMsg;
              });
            }
          }
        });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── BUILD ─────────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final routeManager = context.watch<RouteManagerService>();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_driverName != null ? "สวัสดี $_driverName" : "คนขับรถ"),
        backgroundColor: Colors.purple[700],
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: "แก้ไขชื่อ",
            onPressed: _showDriverNameDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.directions_bus), text: 'จัดการเดินรถ'),
            Tab(icon: Icon(Icons.map), text: 'แผนที่ GPS'),
            Tab(icon: Icon(Icons.calendar_today), text: 'ตารางวันนี้'),
            Tab(icon: Icon(Icons.history), text: 'ประวัติ'),
          ],
        ),
      ),
      body: _driverName == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildManageTab(routeManager),
                _buildMapTab(),
                _buildScheduleTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── TAB 1: จัดการเดินรถ (เดิม) ───────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildManageTab(RouteManagerService routeManager) {
    final dynamicRoutes = routeManager.allRoutes;
    return RefreshIndicator(
      onRefresh: _fetchTodaySchedule,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Driver card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple[50],
                    radius: 30,
                    child: const Icon(
                      Icons.person,
                      color: Colors.purple,
                      size: 30,
                    ),
                  ),
                  title: const Text(
                    "สวัสดีคนขับ",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  subtitle: Text(
                    _driverName!,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple[800],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_note, color: Colors.purple),
                    onPressed: _showDriverNameDialog,
                    tooltip: "แก้ไขชื่อ",
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bus selection
                  const Text(
                    "🚌 เลือกรถที่จะขับ",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBus,
                        hint: Text(
                          _isLoadingSchedule
                              ? "กำลังโหลดตารางเดินรถ..."
                              : (_todaySchedule.isEmpty
                                    ? "ไม่มีตารางเดินรถวันนี้"
                                    : "-- กรุณาเลือกรถ --"),
                        ),
                        disabledHint: Text(
                          _isLoadingSchedule
                              ? "กำลังโหลดตารางเดินรถ..."
                              : "ไม่มีรถว่างให้เลือก",
                        ),
                        isExpanded: true,
                        items: _todaySchedule.keys.map((busId) {
                          String? currentDriver = _busStatus[busId];
                          bool isOccupied =
                              currentDriver != null && currentDriver.isNotEmpty;
                          bool isMine = currentDriver == _driverName;
                          return DropdownMenuItem<String>(
                            value: busId,
                            child: Row(
                              children: [
                                Icon(
                                  isOccupied
                                      ? (isMine ? Icons.person_pin : Icons.lock)
                                      : Icons.check_circle_outline,
                                  color: isOccupied
                                      ? (isMine ? Colors.blue : Colors.red)
                                      : Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: _formatBusName(busId)),
                                        TextSpan(
                                          text: isOccupied
                                              ? (isMine
                                                    ? " (คุณขับอยู่ ✅)"
                                                    : " ($currentDriver ❌)")
                                              : " (ว่าง)",
                                          style: TextStyle(
                                            color: isOccupied
                                                ? (isMine
                                                      ? Colors.blue
                                                      : Colors.red)
                                                : Colors.green,
                                            fontWeight: isOccupied
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedBus = val;
                            if (val != null &&
                                _todaySchedule.containsKey(val)) {
                              _selectedRoute = _todaySchedule[val];
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Route display
                  const Text(
                    "🎨 วันนี้วิ่งสายสีอะไร? (ระบบเลือกให้อัตโนมัติ)",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _resolveRouteDropdownValue(dynamicRoutes),
                        hint: const Text("-- รอเลือกเบอร์รถ --"),
                        isExpanded: true,
                        onChanged: null,
                        icon: const Icon(
                          Icons.lock,
                          size: 16,
                          color: Colors.grey,
                        ),
                        items: dynamicRoutes.map((route) {
                          Color routeColor = route.colorValue == 0xFF000000
                              ? Colors.grey
                              : Color(route.colorValue);
                          return DropdownMenuItem<String>(
                            value: route.routeId,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: routeColor,
                                  radius: 8,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  route.name,
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[700],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _submitData,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        "ยืนยัน / เริ่มงาน",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Release button
                  if (_selectedBus != null)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _releaseBus,
                        icon: const Icon(
                          Icons.stop_circle_outlined,
                          color: Colors.red,
                        ),
                        label: const Text(
                          "เลิกงาน / พักรถ (คืนสถานะว่าง)",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── TAB 2: แผนที่ GPS + Off-Route Alert ──────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMapTab() {
    // ถ้ายังไม่ได้เลือกรถ
    if (_selectedBus == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_bus, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              "กรุณาเลือกรถในแท็บ 'จัดการเดินรถ' ก่อน",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.arrow_back),
              label: const Text("ไปเลือกรถ"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[700],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // เริ่ม listen ตำแหน่งรถ (ถ้ายังไม่ได้เริ่ม)
    if (_myBusPosition == null) {
      _startListeningMyBus(_selectedBus!);
    }

    return Column(
      children: [
        // Off-route alert banner
        if (_isOffRoute)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade700, Colors.orange.shade700],
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _offRouteMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: _isOffRoute ? Colors.red.shade50 : Colors.green.shade50,
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _myBusPosition != null
                      ? (_isOffRoute
                            ? Colors.red
                            : _getRouteColor(_selectedRoute))
                      : Colors.grey,
                  shape: BoxShape.circle,
                  boxShadow: _myBusPosition != null
                      ? [
                          BoxShadow(
                            color:
                                (_isOffRoute
                                        ? Colors.red
                                        : _getRouteColor(_selectedRoute))
                                    .withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _myBusPosition != null
                    ? (_isOffRoute ? "ออกนอกเส้นทาง" : "วิ่งอยู่ในเส้นทาง")
                    : "รอสัญญาณ GPS...",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _isOffRoute
                      ? Colors.red.shade700
                      : _getRouteColor(_selectedRoute),
                ),
              ),
              const Spacer(),
              Text(
                _formatBusName(_selectedBus!),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
            ],
          ),
        ),
        // Map
        Expanded(
          child: _myBusPosition == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        "กำลังรอตำแหน่ง GPS ของรถ...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _myBusPosition!,
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.projectapp',
                    ),
                    // Route polyline
                    if (_routePolyline.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePolyline,
                            strokeWidth: 4.0,
                            color: _getRouteColor(
                              _selectedRoute,
                            ).withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    // Bus marker
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _myBusPosition!,
                          width: 80,
                          height: 80,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _isOffRoute
                                      ? Colors.red
                                      : _getRouteColor(_selectedRoute),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isOffRoute)
                                      const Icon(
                                        Icons.warning,
                                        color: Colors.white,
                                        size: 10,
                                      ),
                                    if (_isOffRoute) const SizedBox(width: 4),
                                    const Text(
                                      "คุณ",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Image.asset(
                                _getBusIconAsset(_selectedRoute),
                                width: 45,
                                height: 45,
                                fit: BoxFit.contain,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  String _getBusIconAsset(String? routeIdentifier) {
    if (routeIdentifier == null) return 'assets/images/busiconall.png';

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
      final c = routeIdentifier.toLowerCase();
      if (c.contains('green') || c.contains('s1')) colorValue = 0xFF44B678;
      if (c.contains('red') || c.contains('s2')) colorValue = 0xFFFF3859;
      if (c.contains('blue') || c.contains('s3') || c.contains('ict'))
        colorValue = 0xFF1177FC;
    }

    if (colorValue == 0xFF44B678) return 'assets/images/bus_green.png';
    if (colorValue == 0xFFFF3859) return 'assets/images/bus_red.png';
    if (colorValue == 0xFF1177FC) return 'assets/images/bus_blue.png';

    return 'assets/images/busiconall.png';
  }

  Color _getRouteColor(String? routeIdentifier) {
    if (routeIdentifier == null) return Colors.purple;

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
      return Color(route.colorValue);
    } catch (_) {}

    final c = routeIdentifier.toLowerCase();
    if (c.contains('green') || c.contains('s1')) return const Color(0xFF44B678);
    if (c.contains('red') || c.contains('s2')) return const Color(0xFFFF3859);
    if (c.contains('blue') || c.contains('s3') || c.contains('ict'))
      return const Color(0xFF1177FC);

    return Colors.purple;
  }

  String _getRouteColorName(String? routeId) {
    if (routeId == null) return 'purple';
    final c = routeId.toLowerCase();
    if (c.contains('green') || c.contains('s1')) return 'green';
    if (c.contains('red') || c.contains('s2')) return 'red';
    if (c.contains('blue') || c.contains('s3') || c.contains('ict')) {
      return 'blue';
    }
    return 'purple';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── TAB 3: ตารางเดินรถวันนี้ ─────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScheduleTab() {
    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            border: Border(bottom: BorderSide(color: Colors.purple.shade200)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.purple.shade700),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ตารางเดินรถวันนี้",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.purple.shade800,
                    ),
                  ),
                  Text(
                    _formatThaiDate(DateTime.now()),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.purple.shade500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _fetchTodaySchedule,
                color: Colors.purple.shade700,
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _isLoadingSchedule
              ? const Center(child: CircularProgressIndicator())
              : _todaySchedule.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "ไม่มีตารางเดินรถวันนี้",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref('GPS').onValue,
                  builder: (context, snapshot) {
                    Map<String, Map<String, dynamic>> liveData = {};
                    if (snapshot.hasData &&
                        snapshot.data?.snapshot.value != null) {
                      final data = snapshot.data!.snapshot.value;
                      if (data is Map) {
                        data.forEach((busId, busData) {
                          if (busData is Map) {
                            Map<dynamic, dynamic> driverData = busData;
                            if (busData.containsKey(busId) &&
                                busData[busId] is Map) {
                              driverData = busData[busId];
                            }
                            liveData[busId.toString()] = {
                              'driverName':
                                  driverData['driverName']?.toString() ?? '',
                              'lat': busData['lat'],
                              'lng': busData['lng'],
                            };
                          }
                        });
                      }
                    }

                    final entries = _todaySchedule.entries.toList();
                    entries.sort((a, b) => a.key.compareTo(b.key));

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final busId = entries[index].key;
                        final routeId = entries[index].value;
                        final live = liveData[busId];
                        final driverName = live?['driverName'] ?? '';
                        final isActive =
                            live != null &&
                            live['lat'] != null &&
                            live['lng'] != null &&
                            driverName.isNotEmpty;
                        final isMine = driverName == _driverName;
                        final routeColor = _getRouteColor(routeId);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: isMine ? 4 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: isMine
                                ? BorderSide(color: Colors.purple, width: 2)
                                : BorderSide.none,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: routeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: routeColor, width: 2),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.directions_bus,
                                    color: routeColor,
                                    size: 20,
                                  ),
                                  Text(
                                    busId.replaceAll('bus_', '#'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: routeColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            title: Text(
                              _formatBusName(busId),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isMine ? Colors.purple : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: routeColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _getRouteName(routeId),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (driverName.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      "🧑‍✈️ $driverName${isMine ? ' (คุณ)' : ''}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isMine
                                            ? Colors.purple
                                            : Colors.grey.shade700,
                                        fontWeight: isMine
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.green
                                        : Colors.grey,
                                    shape: BoxShape.circle,
                                    boxShadow: isActive
                                        ? [
                                            BoxShadow(
                                              color: Colors.green.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: 6,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isActive ? 'LIVE' : 'OFF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isActive
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ─── TAB 4: ประวัติการทำงาน ────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHistoryTab() {
    if (_driverName == null) {
      return const Center(child: Text("กรุณาระบุชื่อก่อน"));
    }

    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: _historyDays));

    return Column(
      children: [
        // Header + filter
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Icon(Icons.history, color: Colors.purple.shade700),
              const SizedBox(width: 8),
              Text(
                "ประวัติงาน: $_driverName",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Day filter chips
              _dayChip(7),
              const SizedBox(width: 4),
              _dayChip(14),
              const SizedBox(width: 4),
              _dayChip(30),
            ],
          ),
        ),
        // List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('bus_operation_logs')
                .where('driver_name', isEqualTo: _driverName)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 60, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(
                        "เกิดข้อผิดพลาด:\n${snapshot.error}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                );
              }

              // Filter by date and sort in-memory (to avoid needing an index)
              final rawDocs = snapshot.data?.docs ?? [];
              final docs = rawDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final ts = data['timestamp'] as Timestamp?;
                if (ts == null) return false;
                return ts.toDate().isAfter(cutoff);
              }).toList();

              // Sort descending by timestamp
              docs.sort((a, b) {
                final tsA =
                    (a.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                final tsB =
                    (b.data() as Map<String, dynamic>)['timestamp']
                        as Timestamp?;
                if (tsA == null || tsB == null) return 0;
                return tsB.compareTo(tsA);
              });

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_toggle_off,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "ไม่พบประวัติงานใน $_historyDays วันล่าสุด",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              // Group by date
              Map<String, List<QueryDocumentSnapshot>> grouped = {};
              for (var doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final ts = data['timestamp'] as Timestamp?;
                if (ts == null) continue;
                final date = ts.toDate();
                final key = "${date.day}/${date.month}/${date.year}";
                grouped.putIfAbsent(key, () => []).add(doc);
              }

              final dateKeys = grouped.keys.toList();

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: dateKeys.length,
                itemBuilder: (context, dateIndex) {
                  final dateStr = dateKeys[dateIndex];
                  final dayDocs = grouped[dateStr]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date header
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "📅 $dateStr",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.purple.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "${dayDocs.length} รายการ",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Entries
                      ...dayDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final busId = data['bus_id'] ?? '';
                        final routeColor = data['route_color'] ?? '';
                        final routeName = data['route_name'] ?? '';
                        final ts = data['timestamp'] as Timestamp?;
                        final timeStr = ts != null
                            ? "${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}"
                            : "-";
                        final color = _getRouteColor(routeColor);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 6, left: 8),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color, width: 1.5),
                              ),
                              child: Icon(
                                Icons.directions_bus,
                                color: color,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              _formatBusName(busId),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    routeName.isNotEmpty
                                        ? routeName
                                        : routeColor,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Text(
                              "🕐 $timeStr",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayChip(int days) {
    final isSelected = _historyDays == days;
    return GestureDetector(
      onTap: () => setState(() => _historyDays = days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.grey.shade300,
          ),
        ),
        child: Text(
          "${days}วัน",
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _formatThaiDate(DateTime dt) {
    final thaiMonths = [
      '',
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final thaiDays = [
      '',
      'จันทร์',
      'อังคาร',
      'พุธ',
      'พฤหัสบดี',
      'ศุกร์',
      'เสาร์',
      'อาทิตย์',
    ];
    return "วัน${thaiDays[dt.weekday]} ที่ ${dt.day} ${thaiMonths[dt.month]} ${dt.year + 543}";
  }
}

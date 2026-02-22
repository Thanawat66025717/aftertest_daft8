import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'models/bus_model.dart';
import 'models/bus_route_data.dart';
import 'services/route_manager_service.dart';
import 'bus_stop_editor_page.dart';
import 'bus_route_editor_page.dart';
import 'login_page.dart';

class EditorHomePage extends StatefulWidget {
  const EditorHomePage({super.key});

  @override
  State<EditorHomePage> createState() => _EditorHomePageState();
}

class _EditorHomePageState extends State<EditorHomePage> {
  final _database = FirebaseDatabase.instance.ref();

  int _currentIndex = 0;
  List<Bus> _buses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToBuses();
  }

  void _listenToBuses() {
    _database.child('GPS').onValue.listen((event) {
      if (!mounted) return;

      final data = event.snapshot.value as Map<dynamic, dynamic>?;

      final Map<String, Bus> busMap = {};

      if (data != null) {
        data.forEach((key, value) {
          if (value is Map) {
            final bus = Bus.fromFirebase(key.toString(), value);
            busMap[bus.id] = bus;
          }
        });
      }

      final List<Bus> loadedBuses = busMap.values.toList();
      // Sort numerically by bus number (e.g., bus_1, bus_2, ... bus_30)
      loadedBuses.sort((a, b) {
        int idA = int.tryParse(a.id.split('_').last) ?? 0;
        int idB = int.tryParse(b.id.split('_').last) ?? 0;
        return idA.compareTo(idB);
      });

      setState(() {
        _buses = loadedBuses;
        _isLoading = false;
      });
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginPage()),
        (route) => false,
      );
    }
  }

  Future<void> _addBus() async {
    final idController = TextEditingController();

    // คำนวณ ID ถัดไปรอไว้เป็น Hint
    final nextSuggested = _buses.isEmpty
        ? 1
        : (_buses
                  .map((b) => int.tryParse(b.id.split('_').last) ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1);

    final String? inputId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มรถบัสใหม่'),
        content: TextField(
          controller: idController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'หมายเลขรถบัส (Bus ID)',
            hintText: '$nextSuggested',
            helperText: 'กรอกเฉพาะตัวเลข เช่น $nextSuggested',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = idController.text.trim();
              if (val.isEmpty) {
                // ถ้าไม่กรอก ให้ใช้ค่าแนะนำ
                Navigator.pop(ctx, nextSuggested.toString());
              } else {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );

    if (inputId == null) return;

    final busId = 'bus_$inputId';

    // เช็คว่ามีอยู่แล้วหรือยัง
    if (_buses.any((b) => b.id == busId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('หมายเลขรถ $inputId มีอยู่ในระบบแล้ว')),
        );
      }
      return;
    }

    await _database.child('GPS').child(busId).set({
      'driverName': '',
      'routeColor': 'white',
      'routeName': 'ว่าง',
      'lastUpdate': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _fillBusGaps() async {
    setState(() => _isLoading = true);
    final existingIds = _buses
        .map((b) => int.tryParse(b.id.split('_').last) ?? 0)
        .toSet();

    for (int i = 1; i <= 30; i++) {
      if (!existingIds.contains(i)) {
        final busId = 'bus_$i';
        await _database.child('GPS').child(busId).set({
          'driverName': '',
          'routeColor': 'white',
          'routeName': 'ว่าง',
          'lastUpdate': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เพิ่มรถบัสที่ขาดหายไปเรียบร้อยแล้ว (1-30)'),
        ),
      );
    }
  }

  Future<void> _removeBus(String busId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('คุณต้องการลบรถบัส $busId ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _database.child('GPS').child(busId).remove();
    }
  }

  Future<void> _updateBusRoute(String busId, String routeId) async {
    final routeManager = Provider.of<RouteManagerService>(
      context,
      listen: false,
    );
    String routeName = 'ว่าง';
    if (routeId != 'white' && routeId != 'unknown') {
      try {
        final route = routeManager.allRoutes.firstWhere(
          (r) => r.routeId == routeId,
        );
        routeName = route.name;
      } catch (_) {}
    }

    await _database.child('GPS').child(busId).update({
      'routeColor': routeId,
      'routeName': routeName,
      'lastUpdate': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Widget build(BuildContext context) {
    final routeManager = context.watch<RouteManagerService>();

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple, Colors.indigo],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          _currentIndex == 0
              ? 'จัดการรถบัส'
              : _currentIndex == 1
              ? 'จัดการป้ายจอด'
              : 'จัดการเส้นทาง',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () async {
              setState(() => _isLoading = true);
              await routeManager.initializeData();
              setState(() => _isLoading = false);
            },
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          if (routeManager.isUsingDefaultData)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.amber.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_off, color: Colors.orange),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ใช้งานข้อมูลเครื่อง',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'ดึงข้อมูลเริ่มต้นเข้าสู่ Cloud เพื่อซิงค์ข้อมูล',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      await routeManager.importDefaults();
                      setState(() => _isLoading = false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text(
                      'ดึงข้อมูล',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _buildBusTab(routeManager),
                const BusStopEditorPage(),
                const BusRouteEditorPage(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: Colors.purple,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_bus),
              activeIcon: Icon(Icons.directions_bus_filled),
              label: 'รถบัส',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.location_on_outlined),
              activeIcon: Icon(Icons.location_on),
              label: 'ป้ายจอด',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'เส้นทาง',
            ),
          ],
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _addBus,
              label: const Text('เพิ่มรถบัส'),
              icon: const Icon(Icons.add_road),
              backgroundColor: Colors.purple,
            )
          : null,
    );
  }

  Widget _buildBusTab(RouteManagerService routeManager) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _buses.length,
            itemBuilder: (context, index) =>
                _buildBusCard(_buses[index], routeManager),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final assignedCount = _buses
        .where(
          (b) =>
              b.routeId != 'unassigned' &&
              b.routeId != 'white' &&
              b.routeId != 'unknown',
        )
        .length;
    final unassignedCount = _buses.length - assignedCount;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ภาพรวมระบบ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatCard('รถทั้งหมด', '${_buses.length}', Colors.purple),
              const SizedBox(width: 12),
              _buildStatCard('จัดสายแล้ว', '$assignedCount', Colors.green),
              const SizedBox(width: 12),
              _buildStatCard('ยังไม่จัดสาย', '$unassignedCount', Colors.orange),
            ],
          ),
          if (_buses.length < 30) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _fillBusGaps,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('สร้างรถบัสส่วนที่ขาด (1-30)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple,
                  side: const BorderSide(color: Colors.purple),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusCard(Bus bus, RouteManagerService routeManager) {
    final route = routeManager.allRoutes.firstWhere(
      (r) => r.routeId == bus.routeId,
      orElse: () => BusRoutes.all.first,
    );

    final bool isUnassigned =
        bus.routeId == 'unassigned' ||
        bus.routeId == 'white' ||
        bus.routeId == 'unknown';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Color(route.colorValue).withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.directions_bus,
              color: Color(route.colorValue),
              size: 28,
            ),
          ),
          title: Text(
            bus.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                      color: isUnassigned
                          ? Colors.grey.shade100
                          : Color(route.colorValue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isUnassigned ? 'ยังไม่ระบุ' : route.shortName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isUnassigned
                            ? Colors.grey
                            : Color(route.colorValue),
                      ),
                    ),
                  ),
                  if (bus.driverName.isNotEmpty &&
                      bus.driverName != 'รอกำหนด') ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.person_outline,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      bus.driverName,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                onSelected: (routeId) => _updateBusRoute(bus.id, routeId),
                itemBuilder: (context) => routeManager.allRoutes.map((r) {
                  return PopupMenuItem(
                    value: r.routeId,
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          color: Color(r.colorValue),
                          size: 12,
                        ),
                        const SizedBox(width: 12),
                        Text(r.name),
                      ],
                    ),
                  );
                }).toList(),
                icon: Icon(Icons.edit_road, color: Colors.purple.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                onPressed: () => _removeBus(bus.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}

import 'package:flutter/material.dart';
import 'sidemenu.dart';

class RoutePage extends StatefulWidget {
  const RoutePage({super.key});

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  // 0 = ภาพรวม, 1 = หน้ามอ, 2 = หอใน, 3 = ICT
  int _selectedRouteView = 0;

  // เมนูล่าง: 0=LiveMaps, 1=BusStop, 2=Route, 3=Plan, 4=Feedback
  int _selectedBottomIndex = 2;

  String get _currentRouteImage {
    switch (_selectedRouteView) {
      case 0:
        return 'assets/images/all.png';
      case 1:
        return 'assets/images/1.png';
      case 2:
        return 'assets/images/2.png';
      case 3:
        return 'assets/images/3.png';
      default:
        return 'assets/images/all.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: const SideMenu(),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Column(
                children: [
                  // --- ส่วนแสดงรูปภาพ ---
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5.0,
                          child: Image.asset(
                            _currentRouteImage,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) {
                              return Container(
                                color: const Color(0xFFE0F2F1),
                                alignment: Alignment.center,
                                child: Text(
                                  'ไม่พบรูปภาพ:\n$_currentRouteImage\n(กรุณาใส่ไฟล์ใน assets)',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  // --- ปุ่มเลือกมุมมองแผนที่ ---
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _routeFilterButton(
                            'ภาพรวม',
                            const Color.fromRGBO(143, 55, 203, 1),
                            0,
                          ),
                          const SizedBox(width: 10),
                          _routeFilterButton(
                            'หน้ามอ',
                            const Color.fromRGBO(68, 182, 120, 1),
                            1,
                          ),
                          const SizedBox(width: 10),
                          _routeFilterButton(
                            'หอใน',
                            const Color.fromRGBO(255, 56, 89, 1),
                            2,
                          ),
                          const SizedBox(width: 10),
                          _routeFilterButton(
                            'ICT',
                            const Color.fromRGBO(17, 119, 252, 1),
                            3,
                          ),
                        ],
                      ),
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

  // Helper สร้างปุ่มตัวกรอง
  Widget _routeFilterButton(String label, Color color, int index) {
    bool isSelected = _selectedRouteView == index;
    return ElevatedButton(
      onPressed: () => setState(() => _selectedRouteView = index),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isSelected
              ? const BorderSide(
                  color: Color.fromRGBO(255, 255, 255, 1),
                  width: 3,
                )
              : BorderSide.none,
        ),
        elevation: isSelected ? 5 : 1,
      ),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  // --- Widgets ย่อย (TopBar, Drawer, BottomBar) ---

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
            'ROUTE MAP',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
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
            _bottomNavItem(0, Icons.location_on, 'Live'), // หน้านี้
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
            break; // อยู่หน้านี้แล้ว
          case 3:
            Navigator.pushReplacementNamed(context, '/plan');
            break;
          case 4:
            Navigator.pushReplacementNamed(context, '/feedback');
            break;
        }
      },
      child: Container(
        // --- ส่วนที่ต้องเพิ่มเพื่อให้มีกรอบขาว ---
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              // ignore: deprecated_member_use
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent, // สีพื้นหลังจางๆ
          borderRadius: BorderRadius.circular(16),
        ),
        // ------------------------------------
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

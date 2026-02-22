import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:projectapp/models/bus_route_data.dart';
import 'sidemenu.dart';
import 'package:provider/provider.dart';
import 'package:projectapp/services/route_manager_service.dart';

// enum BusLine { all, yellow, red, blue } // [REMOVED] Using dynamic routes now

class BusStopPage extends StatefulWidget {
  const BusStopPage({super.key});

  @override
  State<BusStopPage> createState() => _BusStopPageState();
}

class _BusStopPageState extends State<BusStopPage> {
  String? _selectedRouteId; // null = ALL

  // 0=Live, 1=Stop(หน้านี้), 2=Route, 3=Plan, 4=Feed
  int _selectedBottomIndex = 1;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String get _lineTitle {
    if (_selectedRouteId == null) return 'All Stops : ป้ายรถทั้งหมด';

    try {
      final routeManager = Provider.of<RouteManagerService>(
        context,
        listen: false,
      );
      final route = routeManager.allRoutes.firstWhere(
        (r) => r.routeId == _selectedRouteId || r.shortName == _selectedRouteId,
      );
      return '${route.name} (${route.shortName})';
    } catch (_) {
      return '$_selectedRouteId Line';
    }
  }

  Color get _lineColor {
    if (_selectedRouteId == null) return Colors.blueGrey;

    try {
      final routeManager = Provider.of<RouteManagerService>(
        context,
        listen: false,
      );
      final route = routeManager.allRoutes.firstWhere(
        (r) => r.routeId == _selectedRouteId || r.shortName == _selectedRouteId,
      );
      return Color(route.colorValue);
    } catch (_) {
      // Fallback
      if (_selectedRouteId!.contains('S1')) return Colors.green.shade600;
      if (_selectedRouteId!.contains('S2')) return Colors.red.shade600;
      if (_selectedRouteId!.contains('S3')) return Colors.blue.shade700;
      return Colors.purple;
    }
  }

  // เพิ่มตัวแปรสำหรับ Highlight และ Scroll
  String? _targetHighlightName;
  final ScrollController _scrollController = ScrollController();
  bool _shouldScroll = false;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // รับค่าที่ส่งมาจากหน้าแผนที่
    final args = ModalRoute.of(context)?.settings.arguments;

    if (_targetHighlightName != null) return; // ทำครั้งเดียว

    if (args is Map) {
      final name = args['name']?.toString();
      final routeId = args['routeId'];

      if (name != null) {
        // [CHANGE] ไม่ใส่ใน Search แล้ว ให้เก็บไว้ Highlight แทน
        _targetHighlightName = name;
        _shouldScroll = true; // ตั้ง flag ว่าต้องเลื่อนหา
      }

      if (routeId != null) {
        _handleRouteIdSwitch(routeId);
      }
    } else if (args is String && args.isNotEmpty) {
      // Fallback
      _targetHighlightName = args;
      _shouldScroll = true;
    }
  }

  void _handleRouteIdSwitch(dynamic routeData) {
    // routeData อาจจะเป็น String "S1" หรือ List ['S1', 'S2']
    // เราจะเอาตัวแรกที่เจอมาตัดสินใจเปลี่ยน Tab

    String target = '';

    if (routeData is String) {
      target = routeData;
    } else if (routeData is List && routeData.isNotEmpty) {
      target = routeData.first.toString();
    }

    target = target.toUpperCase();
    _selectedRouteId = target.isEmpty ? null : target;
  }

  void _onSelectLine(String? routeId) {
    setState(() => _selectedRouteId = routeId);
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- ส่วนเลือกสาย ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.directions_bus, color: _lineColor),
                            const SizedBox(width: 8),
                            Text(
                              'เลือกสายรถ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment
                              .start, // เปลี่ยนเป็น start เพื่อเลื่อนได้
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _lineCircle(
                                      Colors.blueGrey,
                                      'ALL',
                                      _selectedRouteId == null,
                                      () => _onSelectLine(null),
                                    ),
                                    const SizedBox(width: 8),
                                    ...(() {
                                      final routeManager = context
                                          .read<RouteManagerService>();
                                      final uniqueRoutes = <BusRouteData>[];
                                      final seenNames = <String>{};
                                      for (var r in routeManager.allRoutes) {
                                        if (!seenNames.contains(r.shortName)) {
                                          seenNames.add(r.shortName);
                                          uniqueRoutes.add(r);
                                        }
                                      }
                                      return uniqueRoutes.map(
                                        (route) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8.0,
                                          ),
                                          child: _lineCircle(
                                            Color(route.colorValue),
                                            route.shortName,
                                            _selectedRouteId ==
                                                    route.shortName ||
                                                _selectedRouteId ==
                                                    route.routeId,
                                            () =>
                                                _onSelectLine(route.shortName),
                                          ),
                                        ),
                                      );
                                    })(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- Search ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search, color: _lineColor),
                        hintText: 'ค้นหาชื่อป้าย...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        // Add shadow effect via decoration if possible, but Input decoration is limited.
                        // We rely on elevation of the container if we wrapped it, but here just clean field.
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(color: _lineColor, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- List รายการ ---
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _lineColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _lineColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.alt_route,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _lineTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF5F5F5), // Lighter grey bg
                                ),
                                child: StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('bus_stops')
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError)
                                      return const Center(
                                        child: Text('เกิดข้อผิดพลาด'),
                                      );
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting)
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    if (!snapshot.hasData ||
                                        snapshot.data!.docs.isEmpty)
                                      return const Center(
                                        child: Text('ไม่พบข้อมูล'),
                                      );

                                    var documents = snapshot.data!.docs;
                                    if (_searchQuery.isNotEmpty) {
                                      documents = documents.where((doc) {
                                        var data =
                                            doc.data() as Map<String, dynamic>;
                                        return (data['name'] ?? '')
                                            .toLowerCase()
                                            .contains(
                                              _searchQuery.toLowerCase(),
                                            );
                                      }).toList();
                                    }

                                    // [LOGIC] การกรอง:
                                    // 1. ถ้ามีการค้นหา (Search) -> ให้แสดงทุกสายที่ชื่อตรง (ไม่ต้องสนสี)
                                    // 2. ถ้าไม่มีการค้นหา -> กรองตามสายที่เลือก (สีเขียว/แดง/น้ำเงิน)

                                    if (_searchQuery.isNotEmpty) {
                                      // กรณีค้นหา: กรองแค่ชื่ออย่างเดียว
                                    } else if (_selectedRouteId != null) {
                                      // กรณีไม่ได้ค้นหา: กรองตามสายที่เลือก
                                      final target = _selectedRouteId!
                                          .toUpperCase();

                                      documents = documents.where((doc) {
                                        var data =
                                            doc.data() as Map<String, dynamic>;
                                        var routes =
                                            data['route_id'] ?? data['routeId'];

                                        // ถ้าไม่มี route_id เลย ให้ถือว่าเป็นป้ายจอดทั่วไป (Static) ที่แสดงทุกสาย
                                        if (routes == null) return true;

                                        // กรณี 1: เป็น List (เช่น ['S1', 'S2'])
                                        if (routes is List) {
                                          return routes.any(
                                            (e) => e
                                                .toString()
                                                .toUpperCase()
                                                .trim()
                                                .contains(target),
                                          );
                                        }

                                        // กรณี 2: เป็น String (เช่น "S1" หรือ "S1, S2")
                                        if (routes is String) {
                                          return routes.toUpperCase().contains(
                                            target,
                                          );
                                        }

                                        return true; // Fallback
                                      }).toList();
                                    }

                                    // [LOGIC] Scroll to Target
                                    if (_shouldScroll &&
                                        _targetHighlightName != null) {
                                      // หา index ของป้ายที่ต้องการ
                                      int targetIndex = documents.indexWhere((
                                        doc,
                                      ) {
                                        var data =
                                            doc.data() as Map<String, dynamic>;
                                        return data['name'] ==
                                            _targetHighlightName;
                                      });

                                      if (targetIndex != -1) {
                                        // เจอแล้ว! สั่ง scroll
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (_scrollController
                                                  .hasClients) {
                                                // คำนวณความสูงคร่าวๆ (Tile 72 + Divider 1 = ~73)
                                                _scrollController.jumpTo(
                                                  targetIndex * 75.0,
                                                );
                                              }
                                            });
                                        // reset flag เพื่อไม่ให้ scroll ซ้ำเวลา rebuild
                                        _shouldScroll = false;
                                      }
                                    }

                                    return Scrollbar(
                                      controller: _scrollController,
                                      thumbVisibility:
                                          true, // Show scrollbar always to hint scroll
                                      thickness: 6,
                                      radius: const Radius.circular(10),
                                      child: ListView.builder(
                                        controller: _scrollController,
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          bottom:
                                              60, // Add bottom padding for fade visibility
                                          left: 16,
                                          right: 16,
                                        ),
                                        itemCount: documents.length,
                                        itemBuilder: (context, index) {
                                          final stop =
                                              BusStopData.fromFirestore(
                                                documents[index],
                                              );
                                          final data =
                                              documents[index].data()
                                                  as Map<String, dynamic>;

                                          // เช็คว่าเป็นป้ายปัจจุบันหรือไม่
                                          bool isCurrentStop =
                                              stop.name == _targetHighlightName;

                                          return _buildBusStopCard(
                                            context,
                                            stop,
                                            isCurrentStop,
                                            data,
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // Bottom Fade Gradient
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                height: 40,
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          const Color(
                                            0xFFF5F5F5,
                                          ).withOpacity(0.0),
                                          const Color(0xFFF5F5F5),
                                        ],
                                      ),
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
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // --- Widgets ย่อย ---

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
            'BUS STOP',
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

  Widget _lineCircle(Color c, String label, bool sel, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: sel ? 50 : 40,
            height: sel ? 50 : 40,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: sel ? Border.all(color: Colors.white, width: 3) : null,
              boxShadow: sel
                  ? [
                      BoxShadow(
                        color: c.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (sel)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(Icons.arrow_drop_up, color: c, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildBusStopCard(
    BuildContext context,
    BusStopData stop,
    bool isCurrentStop,
    Map<String, dynamic> data,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: isCurrentStop
            ? Border.all(color: Colors.blue.shade300, width: 2)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pushNamed(
              context,
              '/busStopMap',
              arguments: {
                'id': stop.id,
                'name': stop.name,
                'lat': stop.location?.latitude,
                'long': stop.location?.longitude,
              },
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon / Number
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isCurrentStop
                        ? Colors.blue.shade50
                        : _lineColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCurrentStop
                        ? const Icon(Icons.my_location, color: Colors.blue)
                        : Text(
                            data['stop_id']?.toString() ?? '-',
                            style: TextStyle(
                              color: _lineColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Text Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['name'] ?? 'ป้ายไร้ชื่อ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "พิกัด: ${stop.location?.latitude.toStringAsFixed(4) ?? '-'}, ${stop.location?.longitude.toStringAsFixed(4) ?? '-'}",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildRouteChips(data['route_id']),
                    ],
                  ),
                ),
                // Action Icon
                if (isCurrentStop)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'คุณอยู่ที่นี่',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Icon(Icons.map_outlined, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- [แก้ไข] ส่วน Bottom Bar ใหม่ ---
  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
      ),
      // ลด Padding แนวนอนลงนิดหน่อย เพื่อให้ spaceEvenly ทำงานได้สวยขึ้น
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: SizedBox(
        height: 70,
        child: Row(
          // ใช้ spaceEvenly เพื่อกระจายปุ่มให้ห่างเท่าๆ กัน และไม่ชิดขอบจอ
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bottomNavItem(0, Icons.location_on, 'Live'),
            _bottomNavItem(1, Icons.directions_bus, 'Stop'), // หน้านี้
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
        // เอาพื้นหลังสีขาวออก เพื่อลดความแออัด (หรือจะใส่กลับถ้าชอบก็ได้ครับ)
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

  // Helper สร้าง Chip แสดงสายรถ
  Widget _buildRouteChips(dynamic routesData) {
    if (routesData == null) {
      return const SizedBox.shrink();
    }

    List<String> routes = [];
    if (routesData is List) {
      routes = routesData.map((e) => e.toString()).toList();
    } else if (routesData is String) {
      // ถ้าข้อมูลเป็น String เช่น "S1, S2" ให้แยกด้วยเครื่องหมายจุลภาค
      routes = routesData.split(',').map((e) => e.trim()).toList();
    }

    if (routes.isEmpty) return const SizedBox.shrink();

    // เรียงลำดับ S1, S2, S3
    routes.sort();

    return Wrap(
      spacing: 4,
      children: routes.map((route) {
        Color color = Colors.grey;
        String label = route;
        String upperRoute = route.toUpperCase();

        if (upperRoute.contains('S1')) {
          color = Colors.green.shade600;
          label = 'S1';
        } else if (upperRoute.contains('S2')) {
          color = Colors.red.shade600;
          label = 'S2';
        } else if (upperRoute.contains('S3')) {
          color = Colors.blue.shade700;
          label = 'S3';
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }
}

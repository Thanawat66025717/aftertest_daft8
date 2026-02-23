import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'models/bus_route_data.dart';
import 'services/route_manager_service.dart';

class BusRouteEditorPage extends StatefulWidget {
  const BusRouteEditorPage({super.key});

  @override
  State<BusRouteEditorPage> createState() => _BusRouteEditorPageState();
}

class _BusRouteEditorPageState extends State<BusRouteEditorPage> {
  final _routeManager = RouteManagerService();
  final MapController _mapController = MapController();

  BusRouteData? _editingRoute;
  List<LatLng> _currentPath = [];
  bool _isDrawing = false;
  Map<String, List<LatLng>> _fallbackPaths =
      {}; // Cache สำหรับเส้นทางจาก GeoJSON

  @override
  void initState() {
    super.initState();
    _loadAllFallbackPaths();
  }

  Future<void> _loadAllFallbackPaths() async {
    for (var route in _routeManager.allRoutes) {
      if (route.pathPoints == null || route.pathPoints!.isEmpty) {
        final path = await _loadFallbackPath(route.routeId);
        if (path != null) {
          setState(() {
            _fallbackPaths[route.routeId] = path;
          });
        }
      }
    }
  }

  Future<List<LatLng>?> _loadFallbackPath(String routeId) async {
    String assetPath = '';
    if (routeId == 'S1-PM') {
      assetPath = 'assets/data/bus_route1_pm.geojson';
    } else if (routeId == 'S1-AM' || routeId == 'S1') {
      assetPath = 'assets/data/bus_route1_am.geojson';
    } else if (routeId.contains('S2')) {
      assetPath = 'assets/data/bus_route2.geojson';
    } else if (routeId.contains('S3')) {
      assetPath = 'assets/data/bus_route3.geojson';
    }

    if (assetPath.isEmpty) return null;

    try {
      final jsonData = await DefaultAssetBundle.of(
        context,
      ).loadString(assetPath);
      final json = jsonDecode(jsonData);
      final List<LatLng> points = [];
      final features = json['features'] as List;
      if (features.isNotEmpty) {
        final geometry = features.first['geometry'];
        final coordinates = geometry['coordinates'] as List;
        if (geometry['type'] == 'MultiLineString') {
          for (var line in coordinates) {
            for (var p in line) {
              points.add(
                LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
              );
            }
          }
        } else {
          for (var p in coordinates) {
            points.add(
              LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
            );
          }
        }
      }
      return points;
    } catch (e) {
      return null;
    }
  }

  Future<void> _showAddRouteDialog() async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final shortNameController = TextEditingController();
    int selectedColor = 0xFF9C27B0; // Default purple

    final List<int> colorPresets = [
      0xFF44B678, // เขียว (S1)
      0xFFFF3859, // แดง (S2)
      0xFF1177FC, // ฟ้า (S3)
      0xFF9C27B0, // ม่วง (Default)
      0xFFFFB300, // ส้ม
      0xFFE91E63, // ชมพู
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('สร้างเส้นทางใหม่'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: idController,
                    decoration: const InputDecoration(
                      labelText: 'Route ID (เช่น S4)',
                    ),
                  ),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'ชื่อเต็ม'),
                  ),
                  TextField(
                    controller: shortNameController,
                    decoration: const InputDecoration(labelText: 'ชื่อย่อ'),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'สีประจำสาย:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Color(selectedColor),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hex: #${selectedColor.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'RGB: (${Color(selectedColor).red}, ${Color(selectedColor).green}, ${Color(selectedColor).blue})',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  // Color picker wheel
                  ColorPicker(
                    pickerColor: Color(selectedColor),
                    onColorChanged: (newColor) {
                      setDialogState(() => selectedColor = newColor.value);
                    },
                    pickerAreaHeightPercent: 0.7,
                    enableAlpha: false,
                    displayThumbColor: true,
                    paletteType: PaletteType.hsv,
                    pickerAreaBorderRadius: const BorderRadius.all(
                      Radius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'จิ้มเลือกสีด่วน:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: colorPresets.map((color) {
                      final bool isPicked = selectedColor == color;
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedColor = color),
                        child: Container(
                          width: 35,
                          height: 35,
                          decoration: BoxDecoration(
                            color: Color(color),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isPicked
                                  ? Colors.black
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: isPicked
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (idController.text.isEmpty) return;

                final newRoute = BusRouteData(
                  routeId: idController.text,
                  name: nameController.text,
                  shortName: shortNameController.text,
                  colorValue: selectedColor,
                  stops: [],
                );
                await _routeManager.addRoute(newRoute);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('สร้าง'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRoute(BusRouteData route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('คุณต้องการลบเส้นทาง ${route.name} ใช่หรือไม่?'),
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
      await _routeManager.deleteRoute(route.routeId);
    }
  }

  Future<void> _showEditRouteDetailsDialog(BusRouteData route) async {
    final nameController = TextEditingController(text: route.name);
    final shortNameController = TextEditingController(text: route.shortName);
    int selectedColor = route.colorValue;
    List<BusStopData> editedStops = List.from(route.stops);

    final List<int> colorPresets = [
      0xFF44B678, // เขียว (S1)
      0xFFFF3859, // แดง (S2)
      0xFF1177FC, // ฟ้า (S3)
      0xFF9C27B0, // ม่วง (Default)
      0xFFFFB300, // ส้ม
      0xFFE91E63, // ชมพู
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('แก้ไขรายละเอียดเส้นทาง'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'ชื่อเต็ม'),
                  ),
                  TextField(
                    controller: shortNameController,
                    decoration: const InputDecoration(labelText: 'ชื่อย่อ'),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'สีประจำสาย:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  // Preview และ Hex Code
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Color(selectedColor),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hex: #${selectedColor.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'RGB: (${Color(selectedColor).red}, ${Color(selectedColor).green}, ${Color(selectedColor).blue})',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  // Color picker wheel
                  ColorPicker(
                    pickerColor: Color(selectedColor),
                    onColorChanged: (newColor) {
                      setDialogState(() => selectedColor = newColor.value);
                    },
                    pickerAreaHeightPercent: 0.7,
                    enableAlpha: false,
                    displayThumbColor: true,
                    paletteType: PaletteType.hsv,
                    pickerAreaBorderRadius: const BorderRadius.all(
                      Radius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'จิ้มเลือกสีด่วน (Presets):',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: colorPresets.map((color) {
                      final bool isPicked = selectedColor == color;
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedColor = color),
                        child: Container(
                          width: 35,
                          height: 35,
                          decoration: BoxDecoration(
                            color: Color(color),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isPicked
                                  ? Colors.black
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: [
                              if (isPicked)
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 5,
                                ),
                            ],
                          ),
                          child: isPicked
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ลำดับป้ายรถเมล์:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.blue),
                        onPressed: () async {
                          // แสดง Dialog เลือกป้ายเพิ่ม
                          final BusStopData? selected =
                              await showDialog<BusStopData>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('เลือกป้ายเพิ่ม'),
                                  content: SizedBox(
                                    width: double.maxFinite,
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _routeManager.allStops.length,
                                      itemBuilder: (cc, i) {
                                        final stop = _routeManager.allStops[i];
                                        return ListTile(
                                          title: Text(stop.name),
                                          subtitle: Text(stop.id),
                                          onTap: () => Navigator.pop(c, stop),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                          if (selected != null) {
                            setDialogState(() => editedStops.add(selected));
                          }
                        },
                      ),
                    ],
                  ),
                  const Text(
                    '(ลากเพื่อจัดลำดับ / ปัดซ้ายเพื่อลบ)',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: editedStops.length,
                      onReorder: (oldIndex, newIndex) {
                        setDialogState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = editedStops.removeAt(oldIndex);
                          editedStops.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final stop = editedStops[index];
                        return Dismissible(
                          key: ValueKey('${stop.id}_$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) {
                            setDialogState(() => editedStops.removeAt(index));
                          },
                          child: ListTile(
                            key: ValueKey('${stop.id}_$index'),
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                            title: Text(
                              stop.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setDialogState(
                                      () => editedStops.removeAt(index),
                                    );
                                  },
                                ),
                                const Icon(Icons.drag_handle, size: 20),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedRoute = BusRouteData(
                  routeId: route.routeId,
                  name: nameController.text,
                  shortName: shortNameController.text,
                  colorValue: selectedColor,
                  stops: editedStops,
                  startHour: route.startHour,
                  endHour: route.endHour,
                  pathPoints: route.pathPoints, // พิกัดยังคงเดิมจนกว่าจะวาดใหม่
                );
                await _routeManager.updateRoute(updatedRoute);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_isDrawing) {
      setState(() {
        _currentPath.add(point);
      });
    }
  }

  Future<void> _saveRoute() async {
    if (_editingRoute == null) return;

    final List<GeoPoint> geoPoints = _currentPath
        .map((p) => GeoPoint(p.latitude, p.longitude))
        .toList();

    await _routeManager.updateRoute(_editingRoute!, path: geoPoints);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('บันทึกเส้นทางเรียบร้อยแล้ว')));

    setState(() {
      _isDrawing = false;
      _editingRoute = null;
      _currentPath = [];
    });
  }

  void _selectRoute(BusRouteData route) {
    setState(() {
      _editingRoute = route;
      if (route.pathPoints != null && route.pathPoints!.isNotEmpty) {
        _currentPath = route.pathPoints!
            .map((gp) => LatLng(gp.latitude, gp.longitude))
            .toList();
      } else {
        // ถ้าใน Cloud ไม่มี ให้ดึงจาก Fallback มาเป็นร่างเริ่มต้น
        _currentPath = List.from(_fallbackPaths[route.routeId] ?? []);
      }

      if (_currentPath.isNotEmpty) {
        _mapController.move(_currentPath.first, 15);
      }
    });
  }

  void _startDrawing(BusRouteData route) {
    _selectRoute(route);
    setState(() {
      _isDrawing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _routeManager,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(19.028, 99.895),
                  initialZoom: 15,
                  onTap: _onMapTap,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.app',
                  ),
                  // แสดงเส้นทางทั้งหมดที่มี
                  PolylineLayer(
                    polylines: _routeManager.allRoutes
                        .map((route) {
                          final bool isSelected =
                              _editingRoute?.routeId == route.routeId;

                          // ถ้ากำลังวาดเส้นทางนี้อยู่ ให้ใช้ _currentPath แทน
                          if (isSelected && _currentPath.isNotEmpty) {
                            return Polyline(
                              points: _currentPath,
                              color: Color(route.colorValue),
                              strokeWidth: 5,
                            );
                          }

                          // แสดงเส้นทางปกติ
                          List<LatLng> points =
                              route.pathPoints
                                  ?.map((p) => LatLng(p.latitude, p.longitude))
                                  .toList() ??
                              [];

                          // ถ้าไม่มีพิกัดใน Cloud ให้ใช้ Fallback
                          if (points.isEmpty) {
                            points = _fallbackPaths[route.routeId] ?? [];
                          }

                          return Polyline(
                            points: points,
                            color: isSelected
                                ? Color(route.colorValue)
                                : Color(route.colorValue).withValues(
                                    alpha: 0.3,
                                  ), // จางลงถ้าไม่ได้เลือก
                            strokeWidth: isSelected ? 5 : 3,
                          );
                        })
                        .where((p) => p.points.isNotEmpty)
                        .toList(), // ป้องกัน Crash ถ้าไม่มีพิกัด
                  ),
                  // แสดงจุดหมุดตอนกำลังวาด
                  if (_isDrawing && _currentPath.isNotEmpty)
                    MarkerLayer(
                      markers: _currentPath.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final point = entry.value;
                        final isLast = idx == _currentPath.length - 1;

                        return Marker(
                          point: point,
                          width: 12,
                          height: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isLast ? Colors.red : Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 6,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  MarkerLayer(
                    markers: _routeManager.allStops.map((stop) {
                      final pos = stop.location != null
                          ? LatLng(
                              stop.location!.latitude,
                              stop.location!.longitude,
                            )
                          : const LatLng(0, 0);
                      return Marker(
                        point: pos,
                        width: 30,
                        height: 30,
                        child: Opacity(
                          opacity: _isDrawing ? 0.3 : 1.0,
                          child: Image.asset(
                            'assets/images/bus-stopicon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              _buildOverlayPanel(),
              if (_isDrawing) _buildDrawingControls(),
              if (_isDrawing) _buildDrawingHint(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverlayPanel() {
    if (_isDrawing) return const SizedBox.shrink();

    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ExpansionTile(
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            title: const Text(
              'จัดการเส้นทาง',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    ..._routeManager.allRoutes.map((route) {
                      final bool isSelected =
                          _editingRoute?.routeId == route.routeId;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: Color(
                          route.colorValue,
                        ).withOpacity(0.05),
                        onTap: () => _selectRoute(route),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Color(route.colorValue).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.route,
                            color: Color(route.colorValue),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          route.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          route.routeId,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_note, size: 20),
                              onPressed: () =>
                                  _showEditRouteDetailsDialog(route),
                              tooltip: 'แก้ไขจำลอง',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_location_alt,
                                size: 20,
                              ),
                              onPressed: () => _startDrawing(route),
                              tooltip: 'วาดเส้นทาง',
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _deleteRoute(route),
                            ),
                          ],
                        ),
                      );
                    }),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.green,
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'เพิ่มเส้นทางใหม่',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.green,
                        ),
                      ),
                      onTap: _showAddRouteDialog,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingControls() {
    return Positioned(
      bottom: 30,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color(
                      _editingRoute?.colorValue ?? 0xFF9C27B0,
                    ).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_location_alt,
                    color: Color(_editingRoute?.colorValue ?? 0xFF9C27B0),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'โหมดวาด: ${_editingRoute?.name ?? ""}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDrawingButton(
                  onPressed: _currentPath.isNotEmpty
                      ? () => setState(() => _currentPath.removeLast())
                      : null,
                  icon: Icons.undo,
                  label: 'เลิกทำ',
                  color: Colors.orange,
                ),
                const SizedBox(width: 12),
                _buildDrawingButton(
                  onPressed: () => setState(() => _currentPath = []),
                  icon: Icons.clear_all,
                  label: 'ล้าง',
                  color: Colors.red,
                ),
                const SizedBox(width: 12),
                _buildDrawingButton(
                  onPressed: _saveRoute,
                  icon: Icons.save,
                  label: 'บันทึก',
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _isDrawing = false),
              child: const Text(
                'ยกเลิกการวาด',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawingButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawingHint() {
    return Positioned(
      top: 30,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.indigo.withOpacity(0.9),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, color: Colors.white, size: 18),
              SizedBox(width: 12),
              Text(
                'จิ้มบนแผนที่เพื่อวาดตามจุดต่างๆ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

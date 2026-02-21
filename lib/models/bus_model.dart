import 'package:latlong2/latlong.dart';

class Bus {
  final String id;
  final LatLng position;
  final String name;
  final String routeId;
  final double? distanceToUser;

  // --- เพิ่ม 2 ตัวแปรนี้ ---
  final String driverName; // ชื่อคนขับ
  final String routeColor; // สีสายรถ

  Bus({
    required this.id,
    required this.position,
    required this.name,
    required this.routeId,
    this.distanceToUser,
    required this.driverName, // เพิ่ม
    required this.routeColor, // เพิ่ม
  });

  factory Bus.fromFirebase(String id, Map<dynamic, dynamic> data) {
    // --- ส่วนแก้ปัญหาข้อมูลซ้อนกัน (Nested Fix) ---
    Map<dynamic, dynamic> driverData = data;

    // เช็คว่ามี key ชื่อเหมือน id (เช่น "bus_1") ซ้อนอยู่ข้างในไหม?
    // ถ้ามี แสดงว่าข้อมูลคนขับไปหลบอยู่ในนั้น
    if (data.containsKey(id) && data[id] is Map) {
      driverData = data[id];
      print("ดึงข้อมูลจากชั้นในสำหรับ $id"); // log บอกว่าเจอของซ้อน
    }
    // ------------------------------------------

    return Bus(
      id: id,
      // พิกัด GPS มักจะอยู่ชั้นนอกสุดเสมอ (ใช้ data ตัวเดิม)
      position: LatLng(
        double.parse((data['lat'] ?? 0).toString()),
        double.parse((data['lng'] ?? 0).toString()),
      ),
      name: "รถเบอร์ ${id.split('_').last}",

      // ข้อมูลคนขับ ให้ดึงจาก driverData (ที่แก้ logic แล้ว)
      routeId: driverData['routeColor']?.toString() ?? 'unknown',
      driverName: driverData['driverName']?.toString() ?? '',
      routeColor: driverData['routeColor']?.toString() ?? 'purple',
    );
  }

  Bus copyWithDistance(double dist) {
    return Bus(
      id: id,
      position: position,
      name: name,
      routeId: routeId,
      driverName: driverName,
      routeColor: routeColor, // เพิ่มตรงนี้ด้วย
      distanceToUser: dist,
    );
  }

  Bus copyWithPosition(LatLng newPosition) {
    return Bus(
      id: id,
      position: newPosition,
      name: name,
      routeId: routeId,
      driverName: driverName,
      routeColor: routeColor,
      distanceToUser: distanceToUser,
    );
  }
}
// --- ก๊อปปี้ส่วนนี้ไปวางต่อท้ายไฟล์ bus_model.dart ---

class BusRoute {
  final String id;
  final String name;
  final String shortName;
  final int colorValue;

  const BusRoute({
    required this.id,
    required this.name,
    required this.shortName,
    required this.colorValue,
  });

  // รายการสายรถทั้งหมด
  static List<BusRoute> get allRoutes => [
    const BusRoute(
      id: 'Green',
      name: 'สายหน้ามอ (สีเขียว)',
      shortName: 'หน้ามอ',
      colorValue: 0xFF44B678,
    ),
    const BusRoute(
      id: 'Red',
      name: 'สายหอพัก (สีแดง)',
      shortName: 'หอใน',
      colorValue: 0xFFFF3859,
    ),
    const BusRoute(
      id: 'Blue',
      name: 'สายประตูสาม (สีน้ำเงิน)',
      shortName: 'ICT',
      colorValue: 0xFF1177FC,
    ),
  ];

  static BusRoute? fromId(String id) {
    try {
      return allRoutes.firstWhere(
        (r) => r.id == id || r.id.toLowerCase() == id.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}

import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Service สำหรับคำนวณระยะทางตามเส้นทาง Polyline (Offline)
/// ไม่ต้องเรียก API ภายนอก ใช้ข้อมูล GeoJSON ที่มีอยู่แล้ว
class RouteService {
  static const Distance _haversine = Distance();

  /// คำนวณระยะทางตามเส้นทาง Polyline (เมตร)
  ///
  /// วิธีการ:
  /// 1. หา segment ที่ใกล้ที่สุดบน polyline สำหรับ [from] และ [to]
  /// 2. Project จุดลง segment เป็นจุด "บนเส้นทาง"
  /// 3. วัดระยะตาม polyline ระหว่าง 2 จุดที่ project แล้ว
  ///
  /// คืนค่า null ถ้า routePoints ว่าง
  static double? getPolylineDistance(
    LatLng from,
    LatLng to,
    List<LatLng> routePoints,
  ) {
    if (routePoints.length < 2) return null;

    // 1. หาจุดที่ใกล้ที่สุดบน polyline สำหรับ from และ to
    final fromProj = findClosestProjection(from, routePoints);
    final toProj = findClosestProjection(to, routePoints);

    if (fromProj == null || toProj == null) return null;

    // 2. คำนวณระยะทางตาม polyline ระหว่าง 2 จุด
    return _distanceAlongPolyline(routePoints, fromProj, toProj);
  }

  /// หาจุดที่ project ลงบน polyline ที่ใกล้ที่สุด
  /// คืน RouteProjection ที่มี segmentIndex, projectedPoint, และ distanceToPolyline
  static RouteProjection? findClosestProjection(
    LatLng point,
    List<LatLng> polyline,
  ) {
    double minDist = double.infinity;
    RouteProjection? best;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];

      // Project point onto segment a→b
      final projected = _projectPointOnSegment(point, a, b);
      final dist = _haversine.as(LengthUnit.Meter, point, projected);

      if (dist < minDist) {
        minDist = dist;
        best = RouteProjection(
          segmentIndex: i,
          projectedPoint: projected,
          distToPolyline: dist,
        );
      }
    }

    return best;
  }

  /// Project จุด [p] ลงบน segment [a]→[b]
  /// ใช้ linear interpolation บน lat/lng (ใกล้เคียงเพียงพอสำหรับระยะสั้น)
  static LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;

    if (dx == 0 && dy == 0) return a; // segment มีความยาว 0

    // คำนวณ t (0..1) ที่เป็นตำแหน่ง projection บน segment
    double t =
        ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
        (dx * dx + dy * dy);

    // Clamp t ให้อยู่ในช่วง 0..1
    t = t.clamp(0.0, 1.0);

    return LatLng(a.latitude + t * dy, a.longitude + t * dx);
  }

  /// คำนวณระยะทางตาม polyline ระหว่าง 2 projections
  static double _distanceAlongPolyline(
    List<LatLng> polyline,
    RouteProjection fromProj,
    RouteProjection toProj,
  ) {
    // ให้ startIdx <= endIdx เสมอ (วัดระยะไปทางเดียว)
    int startIdx, endIdx;
    LatLng startPoint, endPoint;

    if (fromProj.segmentIndex <= toProj.segmentIndex) {
      startIdx = fromProj.segmentIndex;
      endIdx = toProj.segmentIndex;
      startPoint = fromProj.projectedPoint;
      endPoint = toProj.projectedPoint;
    } else {
      startIdx = toProj.segmentIndex;
      endIdx = fromProj.segmentIndex;
      startPoint = toProj.projectedPoint;
      endPoint = fromProj.projectedPoint;
    }

    double totalDist = 0;

    if (startIdx == endIdx) {
      // อยู่บน segment เดียวกัน → วัดระยะตรงๆ
      totalDist = _haversine.as(LengthUnit.Meter, startPoint, endPoint);
    } else {
      // segment แรก: จาก startPoint ไปจุดถัดไปของ polyline
      totalDist += _haversine.as(
        LengthUnit.Meter,
        startPoint,
        polyline[startIdx + 1],
      );

      // segments ตรงกลาง
      for (int i = startIdx + 1; i < endIdx; i++) {
        totalDist += _haversine.as(
          LengthUnit.Meter,
          polyline[i],
          polyline[i + 1],
        );
      }

      // segment สุดท้าย: จากจุดเริ่มต้นของ segment ถึง endPoint
      totalDist += _haversine.as(LengthUnit.Meter, polyline[endIdx], endPoint);
    }

    // เพิ่มระยะจากจุดจริงถึง polyline (ระยะ "ตั้งฉาก" ทั้ง 2 ฝั่ง)
    totalDist += fromProj.distToPolyline;
    totalDist += toProj.distToPolyline;

    return totalDist;
  }

  // ล้าง cache (เก็บไว้เผื่อใช้ในอนาคต)
  static void clearCache() {}

  /// หาจุดบนถนนที่ใกล้ที่สุด (Nearest Road Point)
  static Future<LatLng?> getNearestRoadPoint(LatLng point) async {
    final url = Uri.parse(
      'http://router.project-osrm.org/nearest/v1/foot/${point.longitude},${point.latitude}?number=1',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final waypoints = data['waypoints'] as List;
        if (waypoints.isNotEmpty) {
          final location = waypoints[0]['location'] as List;
          return LatLng(location[1], location[0]);
        }
      }
    } catch (e) {
      print('Error finding nearest road point: $e');
    }
    return null;
  }

  /// ดึงเส้นทางเดินเท้าจาก OSRM API
  static Future<List<LatLng>> getWalkingRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/foot/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
    );

    print('Requesting walking route from: $url');

    try {
      final response = await http.get(url);
      print('OSRM Response Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // print('OSRM Response Body: $data');

        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          final geometry = routes[0]['geometry'];
          final coordinates = geometry['coordinates'] as List;
          print('Found walking route with ${coordinates.length} points');
          return coordinates
              .map((coord) => LatLng(coord[1], coord[0]))
              .toList();
        } else {
          print('OSRM returned no routes');
        }
      } else {
        print('OSRM Error: ${response.body}');
      }
    } catch (e) {
      // Handle error or return empty list
      print('Error fetching walking route: $e');
    }

    // Fallback: ถ้าหาเส้นทางไม่ได้ ให้ตีเส้นตรงไปเลย (เพื่อให้ระบบ Simulate ทำงานได้)
    print('OSRM failed, using fallback straight line');
    return [start, end];
  }
}

/// ข้อมูล projection ของจุดลงบน polyline
class RouteProjection {
  final int segmentIndex;
  final LatLng projectedPoint;
  final double distToPolyline;

  RouteProjection({
    required this.segmentIndex,
    required this.projectedPoint,
    required this.distToPolyline,
  });
}

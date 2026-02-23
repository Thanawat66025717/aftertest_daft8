import 'package:cloud_firestore/cloud_firestore.dart';

/// ข้อมูลป้ายรถในแต่ละสาย
class BusStopData {
  final String id;
  final String name;
  final String? shortName;
  final GeoPoint? location;
  final dynamic routes;

  const BusStopData({
    required this.id,
    required this.name,
    this.shortName,
    this.location,
    this.routes,
  });

  factory BusStopData.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // 1. ดึงจาก GeoPoint 'location'
    GeoPoint? geoPoint = data['location'] is GeoPoint ? data['location'] : null;

    // 2. ดึงจากฟิลด์ตัวเลข (lat/long, latitude/longitude)
    double? lat;
    double? lng;
    var rawLat = data['lat'] ?? data['latitude'];
    var rawLng = data['long'] ?? data['lng'] ?? data['longitude'];

    if (rawLat != null) lat = double.tryParse(rawLat.toString());
    if (rawLng != null) lng = double.tryParse(rawLng.toString());

    // Logic การเลือก:
    GeoPoint? finalLoc;
    bool isPlaceholder(double? la, double? lo) {
      if (la == null || lo == null) return true;
      return (la >= 19.028 && la <= 19.031) && (lo >= 99.894 && lo <= 99.896);
    }

    if (!isPlaceholder(lat, lng)) {
      finalLoc = GeoPoint(lat!, lng!);
    } else if (geoPoint != null &&
        !isPlaceholder(geoPoint.latitude, geoPoint.longitude)) {
      finalLoc = geoPoint;
    } else {
      finalLoc =
          geoPoint ??
          ((lat != null && lng != null) ? GeoPoint(lat, lng) : null);
    }

    return BusStopData(
      id: (data['id'] ?? doc.id).toString(),
      name: data['name'] ?? '',
      shortName: data['shortName'],
      location: finalLoc,
      routes: data['route_id'] ?? data['routeId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'shortName': shortName ?? '',
      'location': location,
      'lat': location?.latitude,
      'long': location?.longitude,
      'route_id': routes,
    };
  }

  bool get isPlaceholder {
    if (location == null) return true;
    final la = location!.latitude;
    final lo = location!.longitude;
    // เช็คช่วงกว้างๆ เผื่อทศนิยมต่างกันเล็กน้อย (รอบๆ มหาวิทยาลัยพะเยา)
    return (la >= 19.028 && la <= 19.031) && (lo >= 99.894 && lo <= 99.896);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusStopData &&
          runtimeType == other.runtimeType &&
          id.toLowerCase() == other.id.toLowerCase();

  @override
  int get hashCode => id.toLowerCase().hashCode;

  operator [](String other) {}
}

/// ข้อมูลเส้นทางรถบัสพร้อมลำดับป้าย
class BusRouteData {
  final String routeId;
  final String name;
  final String shortName;
  final int colorValue;
  final List<BusStopData> stops;
  final int? startHour; // null = ตลอดวัน
  final int? endHour;
  final List<GeoPoint>? pathPoints;

  const BusRouteData({
    required this.routeId,
    required this.name,
    required this.shortName,
    required this.colorValue,
    required this.stops,
    this.startHour,
    this.endHour,
    this.pathPoints,
  });

  factory BusRouteData.fromFirestore(
    DocumentSnapshot doc,
    List<BusStopData> allStops, {
    List<GeoPoint>? path,
  }) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // แปลง ID ของป้ายเป็น Object BusStopData
    List<BusStopData> routeStops = [];
    if (data['stops'] != null) {
      List<dynamic> stopIds = data['stops'];
      for (var id in stopIds) {
        final searchId = id.toString().trim();
        // Try exact match first, then case-insensitive
        var stop = allStops.firstWhere(
          (s) => s.id == searchId,
          orElse: () => allStops.firstWhere(
            (s) => s.id.toLowerCase() == searchId.toLowerCase(),
            orElse: () =>
                BusStopData(id: searchId, name: 'Unknown Stop ($searchId)'),
          ),
        );
        routeStops.add(stop);
      }
    }

    int? startHour;
    if (data['startHour'] != null) {
      startHour = int.tryParse(data['startHour'].toString());
    }
    int? endHour;
    if (data['endHour'] != null) {
      endHour = int.tryParse(data['endHour'].toString());
    }

    return BusRouteData(
      routeId: (data['routeId'] ?? doc.id).toString(),
      name: data['name'] ?? '',
      shortName: data['shortName'] ?? '',
      colorValue: data['colorValue'] ?? 0xFF000000,
      startHour: startHour,
      endHour: endHour,
      stops: routeStops,
      pathPoints: path,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'routeId': routeId,
      'name': name,
      'shortName': shortName,
      'colorValue': colorValue,
      'startHour': startHour,
      'endHour': endHour,
      'stops': stops.map((s) => s.id).toList(),
    };
  }

  /// ตรวจสอบว่าสายนี้วิ่งในเวลาที่กำหนดหรือไม่
  bool isActiveAt(DateTime time) {
    if (startHour == null && endHour == null) return true;
    final hour = time.hour;
    if (startHour != null && endHour != null) {
      if (startHour! <= endHour!) {
        return hour >= startHour! && hour < endHour!;
      } else {
        // ข้ามวัน เช่น 14:00 - 00:00
        return hour >= startHour! || hour < endHour!;
      }
    }
    return true;
  }

  /// หา index ของป้ายในสาย (-1 ถ้าไม่มี)
  int indexOfStop(String stopId) {
    return stops.indexWhere((s) => s.id.toLowerCase() == stopId.toLowerCase());
  }

  /// หา index สุดท้ายของป้ายในสาย (สำหรับ loop routes)
  int lastIndexOfStop(String stopId) {
    return stops.lastIndexWhere(
      (s) => s.id.toLowerCase() == stopId.toLowerCase(),
    );
  }

  /// หา indices ทั้งหมดของป้าย (สำหรับป้ายที่ปรากฏหลายครั้ง)
  List<int> allIndicesOfStop(String stopId) {
    List<int> indices = [];
    final searchId = stopId.toLowerCase();
    for (int i = 0; i < stops.length; i++) {
      if (stops[i].id.toLowerCase() == searchId) indices.add(i);
    }
    return indices;
  }

  /// ตรวจสอบว่าป้ายนี้อยู่ในสายหรือไม่
  bool hasStop(String stopId) => indexOfStop(stopId) >= 0;
}

/// ข้อมูลป้ายรถทั้งหมดในระบบ
class BusStops {
  // ป้ายที่ใช้ร่วมกันหลายสาย
  static const namor = BusStopData(
    id: 'namor',
    name: 'สถานีหน้ามหาวิทยาลัยพะเยา',
    shortName: 'หน้ามอ',
    location: GeoPoint(19.0289, 99.8973),
  );
  static const engineering = BusStopData(
    id: 'engineering',
    name: 'สถานีหน้าคณะวิศวกรรมศาสตร์',
    shortName: 'วิศวะ',
    location: GeoPoint(19.0270, 99.8945),
  );
  static const auditorium = BusStopData(
    id: 'auditorium',
    name: 'สถานีหน้าตึกประชุมพญางำเมือง',
    shortName: 'ประชุม',
    location: GeoPoint(19.0255, 99.8930),
  );
  static const president = BusStopData(
    id: 'president',
    name: 'สถานีหน้าตึกอธิการบดีมหาวิทยาลัยพะเยา',
    shortName: 'อธิการบดี',
    location: GeoPoint(19.0245, 99.8920),
  );
  static const arts = BusStopData(
    id: 'arts',
    name: 'สถานีหน้าตึกศิลปศาสตร์',
    shortName: 'ศิลปศาสตร์',
    location: GeoPoint(19.0235, 99.8910),
  );
  static const science = BusStopData(
    id: 'science',
    name: 'สถานีหน้าคณะวิทยาศาสตร์',
    shortName: 'คณะวิทย์',
    location: GeoPoint(19.0225, 99.8900),
  );
  static const pky = BusStopData(
    id: 'pky',
    name: 'จุดจอดรถ PKY',
    shortName: 'PKY',
    location: GeoPoint(19.0210, 99.8890),
  );
  static const ub99 = BusStopData(
    id: 'ub99',
    name: 'สถานีหน้าอาคาร ๙๙ ปี',
    shortName: 'UB99',
    location: GeoPoint(19.030, 99.895),
  );
  static const wiangphayao = BusStopData(
    id: 'wiangphayao',
    name: 'สถานีหน้าเวียงพะเยา',
    shortName: 'เวียงพะเยา',
    location: GeoPoint(19.030, 99.895),
  );
  static const sanguansermsri = BusStopData(
    id: 'sanguansermsri',
    name: 'สถานีหน้าอาคารสงวนเสริมศรี',
    shortName: 'สงวนเสริมศรี',
    location: GeoPoint(19.030, 99.895),
  );
  static const satit = BusStopData(
    id: 'satit',
    name: 'สถานีหน้าโรงเรียนสาธิตมหาวิทยาลัยพะเยา',
    shortName: 'สาธิต',
    location: GeoPoint(19.030, 99.895),
  );
  static const gate3 = BusStopData(
    id: 'gate3',
    name: 'หลังมอประตู 3',
    shortName: 'ประตู3',
    location: GeoPoint(19.035, 99.902), // ประตู 3 มีพิกัดเป็นของตัวเองหน่อย
  );
  static const economyCenter = BusStopData(
    id: 'economy_center',
    name: 'สถานีหน้าศูนย์การเรียนรู้เศรษฐกิจพอเพียง',
    shortName: 'ศูนย์เศรษฐกิจ',
    location: GeoPoint(19.030, 99.895),
  );
  static const ict = BusStopData(
    id: 'ict',
    name: 'สถานีหน้าคณะเทคโนโลยีสารสนเทศ',
    shortName: 'ICT',
    location: GeoPoint(19.030, 99.895),
  );

  /// รายการป้ายทั้งหมด
  static const List<BusStopData> all = [
    namor,
    engineering,
    auditorium,
    president,
    arts,
    science,
    pky,
    ub99,
    wiangphayao,
    sanguansermsri,
    satit,
    gate3,
    economyCenter,
    ict,
  ];

  /// หาป้ายจาก id
  static BusStopData? fromId(String id) {
    try {
      final searchId = id.toLowerCase();
      return all.firstWhere((s) => s.id.toLowerCase() == searchId);
    } catch (_) {
      return null;
    }
  }

  /// หาป้ายจากชื่อ (fuzzy match)
  static BusStopData? fromName(String name) {
    final lower = name.toLowerCase();
    try {
      return all.firstWhere(
        (s) =>
            s.name.toLowerCase().contains(lower) ||
            (s.shortName?.toLowerCase().contains(lower) ?? false) ||
            lower.contains(s.id),
      );
    } catch (_) {
      return null;
    }
  }
}

/// เส้นทางรถบัสทั้งหมด
class BusRoutes {
  /// S1 ก่อน 14:00 (ไม่ผ่าน PKY)
  static const s1AM = BusRouteData(
    routeId: 'S1-AM',
    name: 'หน้ามอ',
    shortName: 'S1',
    colorValue: 0xFF44B678,
    startHour: 5,
    endHour: 14,
    stops: [
      BusStops.namor,
      BusStops.engineering,
      BusStops.auditorium,
      BusStops.president,
      BusStops.arts,
      BusStops.science,
      BusStops.engineering,
      BusStops.namor,
    ],
  );

  /// S1 หลัง 14:00 (ผ่าน PKY)
  static const s1PM = BusRouteData(
    routeId: 'S1-PM',
    name: 'หน้ามอ-PKY',
    shortName: 'S1',
    colorValue: 0xFF44B678,
    startHour: 14,
    endHour: 0,
    stops: [
      BusStops.namor,
      BusStops.engineering,
      BusStops.auditorium,
      BusStops.president,
      BusStops.pky,
      BusStops.arts,
      BusStops.science,
      BusStops.engineering,
      BusStops.namor,
    ],
  );

  /// S2 (วิ่งตลอดวัน)
  static const s2 = BusRouteData(
    routeId: 'S2',
    name: 'หอใน',
    shortName: 'S2',
    colorValue: 0xFFFF3859,
    stops: [
      BusStops.pky,
      BusStops.ub99,
      BusStops.wiangphayao,
      BusStops.sanguansermsri,
      BusStops.satit,
      BusStops.sanguansermsri,
      BusStops.wiangphayao,
      BusStops.ub99,
      BusStops.arts,
      BusStops.science,
      BusStops.auditorium,
      BusStops.president,
      BusStops.pky,
    ],
  );

  /// S3 (วิ่งตลอดวัน)
  static const s3 = BusRouteData(
    routeId: 'S3',
    name: 'ICT',
    shortName: 'S3',
    colorValue: 0xFF1177FC,
    stops: [
      BusStops.gate3,
      BusStops.economyCenter,
      BusStops.auditorium,
      BusStops.president,
      BusStops.arts,
      BusStops.science,
      BusStops.engineering,
      BusStops.ict,
      BusStops.economyCenter,
      BusStops.gate3,
    ],
  );

  /// รายการเส้นทางทั้งหมด
  static const List<BusRouteData> all = [s1AM, s1PM, s2, s3];

  /// หาเส้นทางที่วิ่งในเวลาที่กำหนด
  static List<BusRouteData> getActiveRoutes(DateTime time) {
    return all.where((r) => r.isActiveAt(time)).toList();
  }

  /// หาเส้นทางที่ผ่านป้ายนี้
  static List<BusRouteData> getRoutesWithStop(String stopId, {DateTime? time}) {
    final routes = time != null ? getActiveRoutes(time) : all;
    return routes.where((r) => r.hasStop(stopId)).toList();
  }
}

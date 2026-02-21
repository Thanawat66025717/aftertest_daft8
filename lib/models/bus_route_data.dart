/// ข้อมูลป้ายรถในแต่ละสาย
class BusStopData {
  final String id;
  final String name;
  final String? shortName;

  const BusStopData({required this.id, required this.name, this.shortName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusStopData &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

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

  const BusRouteData({
    required this.routeId,
    required this.name,
    required this.shortName,
    required this.colorValue,
    required this.stops,
    this.startHour,
    this.endHour,
  });

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
    return stops.indexWhere((s) => s.id == stopId);
  }

  /// หา index สุดท้ายของป้ายในสาย (สำหรับ loop routes)
  int lastIndexOfStop(String stopId) {
    return stops.lastIndexWhere((s) => s.id == stopId);
  }

  /// หา indices ทั้งหมดของป้าย (สำหรับป้ายที่ปรากฏหลายครั้ง)
  List<int> allIndicesOfStop(String stopId) {
    List<int> indices = [];
    for (int i = 0; i < stops.length; i++) {
      if (stops[i].id == stopId) indices.add(i);
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
  );
  static const engineering = BusStopData(
    id: 'engineering',
    name: 'สถานีหน้าคณะวิศวกรรมศาสตร์',
    shortName: 'วิศวะ',
  );
  static const auditorium = BusStopData(
    id: 'auditorium',
    name: 'สถานีหน้าตึกประชุมพญางำเมือง',
    shortName: 'ประชุม',
  );
  static const president = BusStopData(
    id: 'president',
    name: 'สถานีหน้าตึกอธิการบดีมหาวิทยาลัยพะเยา',
    shortName: 'อธิการบดี',
  );
  static const arts = BusStopData(
    id: 'arts',
    name: 'สถานีหน้าตึกศิลปศาสตร์',
    shortName: 'ศิลปศาสตร์',
  );
  static const science = BusStopData(
    id: 'science',
    name: 'สถานีหน้าคณะวิทยาศาสตร์',
    shortName: 'คณะวิทย์',
  );
  static const pky = BusStopData(
    id: 'pky',
    name: 'จุดจอดรถ PKY',
    shortName: 'PKY',
  );
  static const ub99 = BusStopData(
    id: 'ub99',
    name: 'สถานีหน้าอาคาร ๙๙ ปี',
    shortName: 'UB99',
  );
  static const wiangphayao = BusStopData(
    id: 'wiangphayao',
    name: 'สถานีหน้าเวียงพะเยา',
    shortName: 'เวียงพะเยา',
  );
  static const sanguansermsri = BusStopData(
    id: 'sanguansermsri',
    name: 'สถานีหน้าอาคารสงวนเสริมศรี',
    shortName: 'สงวนเสริมศรี',
  );
  static const satit = BusStopData(
    id: 'satit',
    name: 'สถานีหน้าโรงเรียนสาธิตมหาวิทยาลัยพะเยา',
    shortName: 'สาธิต',
  );
  static const gate3 = BusStopData(
    id: 'gate3',
    name: 'หลังมอประตู 3',
    shortName: 'ประตู3',
  );
  static const economyCenter = BusStopData(
    id: 'economy_center',
    name: 'สถานีหน้าศูนย์การเรียนรู้เศรษฐกิจพอเพียง',
    shortName: 'ศูนย์เศรษฐกิจ',
  );
  static const ict = BusStopData(
    id: 'ict',
    name: 'สถานีหน้าคณะเทคโนโลยีสารสนเทศ',
    shortName: 'ICT',
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
      return all.firstWhere((s) => s.id == id);
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
    name: 'หน้ามอ (ก่อน 14:00)',
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
    name: 'หน้ามอ-PKY (14:00-00:00)',
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

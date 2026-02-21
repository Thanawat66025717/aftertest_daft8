import 'package:flutter/foundation.dart';
import '../models/bus_route_data.dart';

/// ผลลัพธ์การหาเส้นทาง
class RouteResult {
  final bool found;
  final List<RouteSegment> segments;
  final String message;
  final String? timeNote; // หมายเหตุเวลา เช่น "S1 วิ่งหลัง 14:00"

  const RouteResult({
    required this.found,
    required this.segments,
    required this.message,
    this.timeNote,
  });

  /// ไม่พบเส้นทาง
  factory RouteResult.notFound(String reason) =>
      RouteResult(found: false, segments: [], message: reason);

  /// จำนวนครั้งที่ต้องเปลี่ยนสาย
  int get transferCount => segments.length > 1 ? segments.length - 1 : 0;

  /// เป็นเส้นทางตรงหรือไม่
  bool get isDirect => segments.length == 1;
}

/// ช่วงเส้นทาง (หนึ่งสาย)
class RouteSegment {
  final BusRouteData route;
  final BusStopData fromStop;
  final BusStopData toStop;
  final List<BusStopData> stopsInBetween;
  final bool isLoop;

  const RouteSegment({
    required this.route,
    required this.fromStop,
    required this.toStop,
    required this.stopsInBetween,
    this.isLoop = false,
  });

  /// จำนวนป้ายที่ต้องนั่ง
  int get stopCount => stopsInBetween.length + 1;
}

/// Service สำหรับหาเส้นทางรถบัส
class RoutePlannerService {
  /// หาเส้นทางจากต้นทางไปปลายทาง (คืนเส้นทางที่ดีที่สุด)
  static RouteResult findRoute(
    String fromStopId,
    String toStopId, {
    DateTime? time,
  }) {
    final results = findAllRoutes(fromStopId, toStopId, time: time);
    if (results.isEmpty) {
      final fromStop = BusStops.fromId(fromStopId);
      final toStop = BusStops.fromId(toStopId);
      return RouteResult.notFound(
        'ไม่พบเส้นทางจาก ${fromStop?.shortName ?? fromStopId} ไป ${toStop?.shortName ?? toStopId}',
      );
    }
    return results.first;
  }

  /// หาเส้นทางทั้งหมดจากต้นทางไปปลายทาง (คืนทุกตัวเลือก)
  static List<RouteResult> findAllRoutes(
    String fromStopId,
    String toStopId, {
    DateTime? time,
  }) {
    final now = time ?? DateTime.now();
    final fromStop = BusStops.fromId(fromStopId);
    final toStop = BusStops.fromId(toStopId);

    debugPrint('=== Route Search ===');
    debugPrint('From: $fromStopId -> ${fromStop?.name}');
    debugPrint('To: $toStopId -> ${toStop?.name}');
    debugPrint('Time: ${now.hour}:${now.minute}');

    if (fromStop == null || toStop == null || fromStopId == toStopId) {
      debugPrint('Invalid stops or same stop');
      return [];
    }

    // หาสายที่วิ่งอยู่ตอนนี้
    final activeRoutes = BusRoutes.getActiveRoutes(now);
    debugPrint(
      'Active routes: ${activeRoutes.map((r) => r.shortName).join(", ")}',
    );

    final List<RouteResult> allResults = [];

    // 1. หาเส้นทางตรงทั้งหมด
    final directResults = _findAllDirectRoutes(fromStop, toStop, activeRoutes);
    debugPrint('Direct routes found: ${directResults.length}');
    allResults.addAll(directResults);

    // 2. หาเส้นทางที่ต้องเปลี่ยนสายทั้งหมด
    final transferResults = _findAllTransferRoutes(
      fromStop,
      toStop,
      activeRoutes,
    );
    debugPrint('Transfer routes found: ${transferResults.length}');
    allResults.addAll(transferResults);

    // 3. หาจากสายทั้งหมด (รวมที่ยังไม่วิ่ง) เพื่อแสดงทุกตัวเลือก
    final allRoutes = BusRoutes.all;

    // หา direct routes จากสายทั้งหมด
    final allDirects = _findAllDirectRoutes(fromStop, toStop, allRoutes);
    for (final result in allDirects) {
      final route = result.segments.first.route;

      // ข้ามถ้าเป็นสายที่ active อยู่แล้ว (เพิ่มไปแล้วข้างบน)
      if (activeRoutes.any((r) => r.routeId == route.routeId)) continue;

      String timeNote = _getTimeNoteForRoute(route, result);
      allResults.add(
        RouteResult(
          found: true,
          segments: result.segments,
          message: result.message,
          timeNote: timeNote,
        ),
      );
    }

    // หา transfer routes จากสายทั้งหมด
    final allTransfers = _findAllTransferRoutes(fromStop, toStop, allRoutes);
    for (final result in allTransfers) {
      // ข้ามถ้าทุกสายเป็น active อยู่แล้ว
      final allActive = result.segments.every(
        (s) => activeRoutes.any((r) => r.routeId == s.route.routeId),
      );
      if (allActive) continue;

      String timeNote = _getTimeNoteForTransfer(result);
      allResults.add(
        RouteResult(
          found: true,
          segments: result.segments,
          message: result.message,
          timeNote: timeNote,
        ),
      );
    }

    debugPrint('Total routes found: ${allResults.length}');

    // [UPDATED] เรียงตามคะแนนรวม (Weighted Score) เพื่อให้เส้นทางต่อรถที่มีประสิทธิภาพชนะเส้นทางวนยาวๆ ได้
    allResults.sort((a, b) {
      final aScore = _calculateWeightedScore(a);
      final bScore = _calculateWeightedScore(b);
      return aScore.compareTo(bScore);
    });

    // ลบผลลัพธ์ที่ซ้ำกัน (same first route shortName)
    final seen = <String>{};
    final uniqueResults = <RouteResult>[];
    for (final result in allResults) {
      // Use full route combo as key to allow S1 vs S1-S1 to both appear if different enough
      // But we generally want to dedup if the *experience* is similar.
      // If we use S1-S1 vs S1, keys are "S1-S1" and "S1". They are distinct.
      // So both will appear.
      final key = result.segments.map((s) => s.route.shortName).join('-');
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueResults.add(result);
      }
    }

    // Return top 3 results
    // [UPDATED] คืนค่า 3 อันดับแรก (ซึ่งตอนนี้จะรวม S1->S1 ถ้าคะแนนดีกว่า S1 Loop)
    return uniqueResults.take(3).toList();
  }

  /// คำนวณคะแนน (จำนวนป้าย + penalty ถ้ามีการวนรถ + penalty การต่อรถ)
  static int _calculateWeightedScore(RouteResult result) {
    int penalty = 0;

    // โทษของการวนรถ (Loop)
    for (final seg in result.segments) {
      if (seg.isLoop) penalty += 20; // ให้โทษหนักๆ (20 ป้าย) เพื่อเลี่ยงการวน
    }

    // [NEW] โทษของการต่อรถ (Transfer Penalty)
    // การต่อรถ 1 ครั้ง เทียบเท่ากับการนั่งรถเพิ่มประมาณ 5 ป้าย (ลดจาก infinity เพื่อให้ชนะ loop ได้)
    if (result.transferCount > 0) {
      penalty += (result.transferCount * 5);
    }

    final stops = result.segments.fold<int>(0, (sum, s) => sum + s.stopCount);
    return stops + penalty;
  }

  /// สร้าง time note สำหรับ direct route ที่ยังไม่วิ่ง
  static String _getTimeNoteForRoute(BusRouteData route, RouteResult result) {
    // ตรวจสอบกรณี S1-PM ที่ไป PKY
    if (route.routeId == 'S1-PM') {
      final involvesPKY = result.segments.any(
        (s) =>
            s.fromStop.id == 'pky' ||
            s.toStop.id == 'pky' ||
            s.stopsInBetween.any((stop) => stop.id == 'pky'),
      );
      if (involvesPKY) {
        return '⚠️ S1 ไป PKY ได้ตั้งแต่ 14:00 น. เป็นต้นไป';
      }
    }

    if (route.startHour != null && route.endHour != null) {
      return '⏰ ${route.shortName} วิ่ง ${route.startHour}:00-${route.endHour}:00 น.';
    } else if (route.startHour != null) {
      return '⏰ ${route.shortName} วิ่งตั้งแต่ ${route.startHour}:00 น.';
    }
    return '';
  }

  /// สร้าง time note สำหรับ transfer route ที่มีสายยังไม่วิ่ง
  static String _getTimeNoteForTransfer(RouteResult result) {
    final List<String> notes = [];

    for (final segment in result.segments) {
      final route = segment.route;

      // ตรวจสอบกรณี S1-PM ที่ไป PKY
      if (route.routeId == 'S1-PM') {
        final involvesPKY =
            segment.fromStop.id == 'pky' ||
            segment.toStop.id == 'pky' ||
            segment.stopsInBetween.any((stop) => stop.id == 'pky');
        if (involvesPKY) {
          return '⚠️ S1 ไป PKY ได้ตั้งแต่ 14:00 น. เป็นต้นไป';
        }
      }

      if (route.startHour != null && route.endHour != null) {
        notes.add(
          '${route.shortName}: ${route.startHour}:00-${route.endHour}:00',
        );
      } else if (route.startHour != null) {
        notes.add('${route.shortName}: ตั้งแต่ ${route.startHour}:00');
      }
    }

    if (notes.isNotEmpty) {
      return '⏰ ${notes.join(", ")} น.';
    }
    return '';
  }

  /// หาเส้นทางตรงทั้งหมด (ใช้สายเดียว)
  /// Helper: ตรวจสอบว่าเป็นเส้นทางวนลูปหรือไม่
  /// [UPDATED] Helper: เช็คว่าเป็นสายรถวนหรือไม่ (ต้นทาง code เดียวกับปลายทาง)
  /// ใช้สำหรับระบุว่าสายนี้สามารถวิ่งวนกลับมาที่เดิมได้ (Circular Route)
  static bool _isCircular(BusRouteData route) {
    if (route.stops.isEmpty) return false;
    return route.stops.first.id == route.stops.last.id;
  }

  /// Helper: คำนวณระยะทาง (จำนวนป้าย)
  static int _calculateStopCount(
    int fromIdx,
    int toIdx, [
    int totalLen = 0,
    bool isCircular = false,
  ]) {
    if (fromIdx < toIdx) {
      return toIdx - fromIdx;
    } else if (isCircular && fromIdx > toIdx) {
      return (totalLen - 1 - fromIdx) + toIdx;
    }
    return 999;
  }

  /// Helper: ดึงป้ายระหว่างทาง
  static List<BusStopData> _getStopsInBetween(
    BusRouteData route,
    int fromIdx,
    int toIdx, [
    bool isCircular = false,
  ]) {
    final stops = <BusStopData>[];
    if (fromIdx < toIdx) {
      for (int i = fromIdx + 1; i < toIdx; i++) {
        stops.add(route.stops[i]);
      }
    } else if (isCircular && fromIdx > toIdx) {
      for (int i = fromIdx + 1; i < route.stops.length; i++) {
        stops.add(route.stops[i]);
      }
      for (int i = 1; i < toIdx; i++) {
        stops.add(route.stops[i]);
      }
    }
    return stops;
  }

  static String _generateMessageFromSegments(List<RouteSegment> segments) {
    if (segments.isEmpty) return '';

    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (i == 0) {
        buffer.write(
          'ขึ้น ${seg.route.shortName} ไปลง ${seg.toStop.shortName ?? seg.toStop.name}',
        );
      } else {
        buffer.write(
          ' แล้วต่อ ${seg.route.shortName} ไป ${seg.toStop.shortName ?? seg.toStop.name}',
        );
      }
    }
    return buffer.toString();
  }

  /// Helper: แบ่ง segment ถ้าผ่าน PKY (ต้องเปลี่ยนรถ)
  static List<RouteSegment> _splitIfPassingTerminal(
    List<RouteSegment> originalSegments,
  ) {
    final List<RouteSegment> newSegments = [];

    for (final seg in originalSegments) {
      // เช็คว่าผ่าน PKY หรือ ประตู 3 หรือไม่ (ใน stopsInBetween)
      final terminalIndex = seg.stopsInBetween.indexWhere(
        (s) => s.id == 'pky' || s.id == 'gate3',
      );

      if (terminalIndex != -1) {
        // เจอ Terminal ในระหว่างทาง -> ต้องแบ่งครึ่ง
        final terminalStop = seg.stopsInBetween[terminalIndex];

        // Segment 1: From -> Terminal
        final stops1 = seg.stopsInBetween.sublist(0, terminalIndex);
        newSegments.add(
          RouteSegment(
            route: seg.route,
            fromStop: seg.fromStop,
            toStop: terminalStop,
            stopsInBetween: stops1,
            isLoop: false, // แบ่งแล้วไม่ถือว่าเป็น loop ใหญ่
          ),
        );

        // Segment 2: Terminal -> To
        final stops2 = seg.stopsInBetween.sublist(terminalIndex + 1);
        newSegments.add(
          RouteSegment(
            route: seg.route,
            fromStop: terminalStop,
            toStop: seg.toStop,
            stopsInBetween: stops2,
            isLoop: false,
          ),
        );
      } else {
        // ไม่ผ่าน PKY -> ใช้ segment เดิม
        newSegments.add(seg);
      }
    }
    return newSegments;
  }

  static List<RouteResult> _findAllDirectRoutes(
    BusStopData fromStop,
    BusStopData toStop,
    List<BusRouteData> routes,
  ) {
    final List<RouteResult> results = [];

    for (final route in routes) {
      // หา indices ทั้งหมดของต้นทางและปลายทาง (สำหรับ loop routes)
      final fromIndices = route.allIndicesOfStop(fromStop.id);
      final toIndices = route.allIndicesOfStop(toStop.id);
      final isCircular = _isCircular(route);

      // ลองทุกคู่ของ fromIndex และ toIndex
      for (final fromIndex in fromIndices) {
        for (final toIndex in toIndices) {
          final isLoopSegment = isCircular && fromIndex > toIndex;

          // กรณีปกติ (forward) หรือ กรณีวนลูป (backward but circular)
          if (fromIndex < toIndex || isLoopSegment) {
            // เก็บป้ายระหว่างทาง
            final stopsInBetween = _getStopsInBetween(
              route,
              fromIndex,
              toIndex,
              isCircular,
            );

            // ตรวจสอบและแบ่ง segment หากผ่าน PKY
            final rawSegments = [
              RouteSegment(
                route: route,
                fromStop: fromStop,
                toStop: toStop,
                stopsInBetween: stopsInBetween,
                isLoop: isLoopSegment,
              ),
            ];
            final finalSegments = _splitIfPassingTerminal(rawSegments);

            results.add(
              RouteResult(
                found: true,
                segments: finalSegments,
                message: _generateMessageFromSegments(finalSegments),
              ),
            );
          }
        }
      }
    }
    return results;
  }

  /// หาเส้นทางที่ต้องเปลี่ยนสายทั้งหมด (สองสาย)
  static List<RouteResult> _findAllTransferRoutes(
    BusStopData fromStop,
    BusStopData toStop,
    List<BusRouteData> routes,
  ) {
    // หาสายที่ผ่านต้นทาง
    final fromRoutes = routes.where((r) => r.hasStop(fromStop.id)).toList();
    // หาสายที่ผ่านปลายทาง
    final toRoutes = routes.where((r) => r.hasStop(toStop.id)).toList();

    final List<RouteResult> results = [];
    final Set<String> seenRouteKeys = {};

    for (final firstRoute in fromRoutes) {
      final isFirstCircular = _isCircular(firstRoute);
      for (final secondRoute in toRoutes) {
        // [UPDATED] Remove this check to allow S1->S1 transfer
        // if (firstRoute.routeId == secondRoute.routeId) continue;
        final isSecondCircular = _isCircular(secondRoute);

        // หาจุดเปลี่ยนสาย (ป้ายที่อยู่ในทั้งสองสาย)
        final transferStops = _findTransferPoints(firstRoute, secondRoute);

        RouteResult? bestForThisPair;
        int bestStopCount = 999;

        debugPrint(
          'Checking ${firstRoute.shortName} (Circular: $isFirstCircular) -> ${secondRoute.shortName} (Circular: $isSecondCircular)',
        );

        for (final transferStop in transferStops) {
          // [NEW] ป้องกันการต่อรถสายเดิมที่จุดอื่นที่ไม่ใช่ Terminal (PKY หรือ Gate 3)
          // [UPDATED] อนุญาตให้ต่อรถที่ "คณะวิศวะ" (engineering) ได้ด้วย ตามคำแนะนำผู้ใช้
          final isSameRoute = firstRoute.shortName == secondRoute.shortName;
          final isTerminal =
              transferStop.id == 'pky' ||
              transferStop.id == 'gate3' ||
              transferStop.id == 'engineering';

          if (isSameRoute && !isTerminal) {
            continue;
          }

          // หา indices ทั้งหมดสำหรับแต่ละป้าย
          final firstFromIndices = firstRoute.allIndicesOfStop(fromStop.id);
          final firstToIndices = firstRoute.allIndicesOfStop(transferStop.id);
          final secondFromIndices = secondRoute.allIndicesOfStop(
            transferStop.id,
          );
          final secondToIndices = secondRoute.allIndicesOfStop(toStop.id);

          // ลองทุกคู่ของ indices
          for (final firstFromIdx in firstFromIndices) {
            for (final firstToIdx in firstToIndices) {
              final isSeg1Loop = isFirstCircular && firstFromIdx > firstToIdx;
              if (!(firstFromIdx < firstToIdx || isSeg1Loop)) continue;

              for (final secondFromIdx in secondFromIndices) {
                for (final secondToIdx in secondToIndices) {
                  final isSeg2Loop =
                      isSecondCircular && secondFromIdx > secondToIdx;
                  if (!(secondFromIdx < secondToIdx || isSeg2Loop)) continue;

                  // นับจำนวนป้าย
                  final totalStops =
                      _calculateStopCount(
                        firstFromIdx,
                        firstToIdx,
                        firstRoute.stops.length,
                        isFirstCircular,
                      ) +
                      _calculateStopCount(
                        secondFromIdx,
                        secondToIdx,
                        secondRoute.stops.length,
                        isSecondCircular,
                      );

                  // Calculate score with penalty
                  int currentPenalty = 0;
                  if (isSeg1Loop) currentPenalty += 20;
                  if (isSeg2Loop) currentPenalty += 20;
                  final totalScore = totalStops + currentPenalty;

                  if (totalScore < bestStopCount) {
                    bestStopCount = totalScore;

                    final stops1 = _getStopsInBetween(
                      firstRoute,
                      firstFromIdx,
                      firstToIdx,
                      isFirstCircular,
                    );
                    final stops2 = _getStopsInBetween(
                      secondRoute,
                      secondFromIdx,
                      secondToIdx,
                      isSecondCircular,
                    );

                    // Old message logic removed, using generator
                    // String msg = ...

                    final rawSegments = [
                      RouteSegment(
                        route: firstRoute,
                        fromStop: fromStop,
                        toStop: transferStop,
                        stopsInBetween: stops1,
                        isLoop: isSeg1Loop,
                      ),
                      RouteSegment(
                        route: secondRoute,
                        fromStop: transferStop,
                        toStop: toStop,
                        stopsInBetween: stops2,
                        isLoop: isSeg2Loop,
                      ),
                    ];

                    final finalSegments = _splitIfPassingTerminal(rawSegments);

                    bestForThisPair = RouteResult(
                      found: true,
                      segments: finalSegments,
                      message: _generateMessageFromSegments(finalSegments),
                    );
                  }
                }
              }
            }
          }
        }

        // เพิ่มผลลัพธ์ที่ดีที่สุดสำหรับ pair นี้ (ถ้ายังไม่มี)
        if (bestForThisPair != null) {
          final key = '${firstRoute.shortName}-${secondRoute.shortName}';
          if (!seenRouteKeys.contains(key)) {
            seenRouteKeys.add(key);
            results.add(bestForThisPair);
          }
        }
      }
    }

    return results;
  }

  /// หาจุดเปลี่ยนสาย (ป้ายที่อยู่ในทั้งสองสาย)
  static List<BusStopData> _findTransferPoints(
    BusRouteData route1,
    BusRouteData route2,
  ) {
    final stops1 = route1.stops.toSet();
    final stops2 = route2.stops.toSet();
    return stops1.intersection(stops2).toList();
  }

  /// แปลง stop id จาก Firebase เป็น internal id
  static String? mapFirebaseIdToStopId(String firebaseId, String stopName) {
    // ลองหาจากชื่อก่อน
    final fromName = BusStops.fromName(stopName);
    if (fromName != null) return fromName.id;

    // Mapping พิเศษ
    final nameLower = stopName.toLowerCase();
    if (nameLower.contains('pky') || nameLower.contains('พีเค')) return 'pky';
    if (nameLower.contains('หลังมอ') ||
        (nameLower.contains('ประตู') && nameLower.contains('3'))) {
      return 'gate3';
    }
    if (nameLower.contains('หน้ามอ') || nameLower.contains('namor')) {
      return 'namor';
    }
    if (nameLower.contains('วิศว') || nameLower.contains('engineering')) {
      return 'engineering';
    }
    if (nameLower.contains('ประชุม') || nameLower.contains('พญางำเมือง')) {
      return 'auditorium';
    }
    if (nameLower.contains('อธิการ') || nameLower.contains('president')) {
      return 'president';
    }
    if (nameLower.contains('ศิลป') || nameLower.contains('arts')) {
      return 'arts';
    }
    if (nameLower.contains('science') ||
        nameLower.contains('วิทยาศาสตร์') ||
        nameLower.contains('คณะวิทย์') ||
        nameLower.contains('พยา')) {
      return 'science';
    }
    if (nameLower.contains('99') ||
        nameLower.contains('๙๙') ||
        nameLower.contains('ub')) {
      return 'ub99';
    }
    if (nameLower.contains('เวียง')) {
      return 'wiangphayao';
    }
    if (nameLower.contains('สงวน') || nameLower.contains('เสริมศรี')) {
      return 'sanguansermsri';
    }
    if (nameLower.contains('สาธิต') || nameLower.contains('satit')) {
      return 'satit';
    }
    if (nameLower.contains('เศรษฐกิจ') || nameLower.contains('economy')) {
      return 'economy_center';
    }
    if (nameLower.contains('ict') || nameLower.contains('เทคโนโลยีสารสนเทศ')) {
      return 'ict';
    }

    return null;
  }
}

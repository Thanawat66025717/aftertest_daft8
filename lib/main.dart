import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

import 'package:projectapp/busstop-page.dart';
import 'package:projectapp/feedback-page.dart';
import 'package:projectapp/route-page.dart';
import 'package:projectapp/upbus-page.dart';
import 'package:projectapp/plan-page.dart';
// import 'change_route_page.dart'; // ลบออกเนื่องจากไม่ได้ใช้งานในไฟล์นี้

// --- [เพิ่ม Import ตรงนี้] ---
import 'package:projectapp/busstop_map_page.dart';
import 'package:projectapp/login_page.dart';
// -------------------------

// Import Global Location Service และ Debug Bar
import 'package:projectapp/services/global_location_service.dart';
// import 'package:projectapp/widgets/global_debug_bar.dart'; // ลบออกเนื่องจากไม่ได้ใช้งานแล้ว

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Global Location Service
  final globalLocationService = GlobalLocationService();
  // Note: We do NOT await initialize() here to prevent white screen hang.
  // Initialization is moved to UpBusHomePage.

  runApp(
    ChangeNotifierProvider.value(
      value: globalLocationService,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UP BUS',
      theme: ThemeData(
        primaryColor: const Color(0xFF9C27B0),
        useMaterial3: false,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const UpBusHomePage(),
        '/busStop': (context) => const BusStopPage(),
        '/route': (context) => const RoutePage(),
        '/plan': (context) => const PlanPage(),
        '/feedback': (context) => const FeedbackPage(),
        '/login': (context) => LoginPage(),

        // --- [เพิ่ม Route ตรงนี้] ---
        // นี่คือส่วนที่แก้ Error: Could not find a generator for route
        '/busStopMap': (context) => const BusStopMapPage(),
        // ------------------------
      },
    );
  }
}

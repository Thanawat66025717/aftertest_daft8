import 'package:flutter/material.dart';

/// Widget ที่ห่อหุ้มทุกหน้า (ไม่แสดงอะไรเพิ่มเติมแล้ว)
class GlobalDebugBarWrapper extends StatelessWidget {
  final Widget child;

  const GlobalDebugBarWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // แสดงเฉพาะหน้าหลัก ไม่มี Debug Bar แล้ว
    return child;
  }
}

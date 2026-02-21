import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // import ตัวนี้
// import 'package:projectapp/login_page.dart'; // ลบออกเนื่องจากใช้ Named Route แล้ว
import 'package:projectapp/change_route_page.dart'; // เช็ค path ให้ถูก
import 'package:projectapp/manager_page.dart'; // import หน้า Manager

class SideMenu extends StatefulWidget {
  const SideMenu({Key? key}) : super(key: key);

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  // รายชื่อคนขับ (Driver Email)
  final List<String> driverEmails = [
    'driver@upbus.com',
    'thanawatj3@gmail.com',
  ];

  // รายชื่อผู้จัดการ (Manager Email)
  final List<String> managerEmails = ['admin@upbus.com', 'manager@upbus.com'];

  @override
  Widget build(BuildContext context) {
    // ดึง User ปัจจุบัน
    final user = FirebaseAuth.instance.currentUser;
    // เช็คว่าเป็นคนขับหรือไม่
    bool isDriver = user != null && driverEmails.contains(user.email);
    // เช็คว่าเป็นผู้จัดการหรือไม่
    bool isManager = user != null && managerEmails.contains(user.email);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // --- ส่วนหัว (Header) ---
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              color: const Color(0xFF9C27B0),
              width: double.infinity,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      isManager ? Icons.admin_panel_settings : Icons.person,
                      size: 35,
                      color: Colors.purple,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user != null ? (user.email ?? "ผู้ใช้งาน") : "ผู้เยี่ยมชม",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isManager)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'ผู้จัดการ',
                        style: TextStyle(
                          color: Color(0xFF9C27B0),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // --- เมนูทั่วไป ---
            const Divider(),

            // ===============================================
            // เงื่อนไขการแสดงปุ่ม
            // ===============================================

            // 0. ถ้าเป็นผู้จัดการ -> ปุ่มไปหน้าผู้จัดการ
            if (isManager)
              ListTile(
                leading: const Icon(Icons.dashboard, color: Colors.purple),
                title: const Text('หน้าผู้จัดการ'),
                subtitle: const Text('ดู Feedback และคนขับ'),
                onTap: () {
                  Navigator.pop(context); // ปิดเมนู
                  // ไปหน้าผู้จัดการ
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManagerPage(),
                    ),
                  );
                },
              ),

            // 1. ถ้าเป็นคนขับ -> ปุ่มจัดการเดินรถ
            if (isDriver)
              ListTile(
                leading: const Icon(
                  Icons.directions_bus_filled,
                  color: Colors.purple,
                ),
                title: const Text('จัดการเดินรถ (Driver)'),
                subtitle: const Text('เปลี่ยนสาย / เลือกเบอร์รถ'),
                onTap: () {
                  Navigator.pop(context); // ปิดเมนู
                  // ไปหน้าจัดการเดินรถ (ChangeRoutePage)
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChangeRoutePage(),
                    ),
                  );
                },
              ),

            // 2. ถ้ายังไม่ล็อกอิน -> ปุ่มเข้าสู่ระบบ
            if (user == null)
              ListTile(
                leading: const Icon(Icons.login, color: Colors.green),
                title: const Text('เข้าสู่ระบบ'),
                subtitle: const Text('สำหรับเจ้าหน้าที่/คนขับ'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  nav.pop(); // ปิดเมนู (Drawer)

                  // รอให้ Drawer ปิดสนิทนิดนึงก่อนค่อยสั่ง Push เพื่อความเสถียรสูงสุด
                  Future.microtask(() {
                    nav.pushNamed('/login');
                  });

                  // เมื่อกลับมาให้รีเฟรชหน้าเพื่ออัปเดตเมนู
                  setState(() {});
                },
              ),

            const Spacer(),

            // 3. ปุ่ม Logout (แสดงเมื่อล็อกอินแล้ว)
            if (user != null)
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout'),
                onTap: () async {
                  // 1. ล้างชื่อคนขับออกจากเครื่อง (เพื่อให้ครั้งหน้าต้องกรอกใหม่)
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('saved_driver_name');

                  // 2. ออกจากระบบ Firebase
                  await FirebaseAuth.instance.signOut();

                  if (!mounted) return;
                  Navigator.pop(context); // ปิดเมนู

                  // 3. แจ้งเตือนและรีเฟรชเมนู
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ออกจากระบบเรียบร้อย')),
                  );
                  setState(
                    () {},
                  ); // รีเฟรชให้ปุ่ม Driver หายไป ปุ่ม Login กลับมา
                },
              ),
          ],
        ),
      ),
    );
  }
}

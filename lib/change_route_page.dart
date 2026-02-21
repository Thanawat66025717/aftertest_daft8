import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'upbus-page.dart'; // ตรวจสอบว่าชื่อไฟล์นี้ตรงกับของคุณนะครับ

class ChangeRoutePage extends StatefulWidget {
  const ChangeRoutePage({super.key});

  @override
  State<ChangeRoutePage> createState() => _ChangeRoutePageState();
}

class _ChangeRoutePageState extends State<ChangeRoutePage> {
  String? _driverName; // ชื่อคนขับปัจจุบัน
  String? _selectedBus; // รถที่เลือก
  String? _selectedRoute; // สีสายรถ

  // เก็บสถานะรถจาก Firebase (Key=เบอร์รถ, Value=ชื่อคนขับ)
  Map<String, String> _busStatus = {};

  final List<String> _allBusIds = List.generate(
    30,
    (index) => "bus_${index + 1}",
  );

  final List<Map<String, dynamic>> _routeList = [
    {
      "name": "สายหน้ามอ (สีเขียว)",
      "color": const Color.fromRGBO(68, 182, 120, 1),
      "value": "green",
    },
    {
      "name": "สายหอพัก (สีแดง)",
      "color": const Color.fromRGBO(255, 56, 89, 1),
      "value": "red",
    },
    {
      "name": "สายประตูสาม (สีน้ำเงิน)",
      "color": const Color.fromRGBO(17, 119, 252, 1),
      "value": "blue",
    },
  ];

  // Schedule Data
  Map<String, String> _todaySchedule = {};
  bool _isLoadingSchedule = true;

  @override
  void initState() {
    super.initState();
    // 1. เช็คก่อนเลยว่าเคยเมมชื่อไว้ไหม
    _checkSavedDriverName();

    // 2. ฟังค่าจาก Firebase
    _listenToBusStatusRealtime();

    // 3. โหลดตารางเดินรถวันนี้
    _fetchTodaySchedule();
  }

  // ฟังก์ชันโหลดชื่อจากเครื่อง
  Future<void> _checkSavedDriverName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedName = prefs.getString('saved_driver_name');

    if (savedName != null && savedName.isNotEmpty) {
      setState(() {
        _driverName = savedName;
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDriverNameDialog();
      });
    }
  }

  Future<void> _fetchTodaySchedule() async {
    final now = DateTime.now();
    final dateStr = "${now.year}-${now.month}-${now.day}";
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bus_schedule')
          .doc(dateStr)
          .get();

      if (mounted) {
        setState(() {
          _isLoadingSchedule = false;
          if (snapshot.exists && snapshot.data() != null) {
            _todaySchedule.clear();
            snapshot.data()!.forEach((key, value) {
              // key = bus_id, value = route (green/red/blue)
              if (key.startsWith('bus_')) {
                _todaySchedule[key] = value.toString();
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching schedule: $e");
      if (mounted) setState(() => _isLoadingSchedule = false);
    }
  }

  // ฟังก์ชันแสดง Popup ถามชื่อ (และบันทึก)
  Future<void> _showDriverNameDialog() async {
    if (!mounted) return;
    final TextEditingController nameController = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Row(
              children: [
                Icon(Icons.badge, color: Colors.purple),
                SizedBox(width: 10),
                Text("ระบุตัวตน"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("กรุณากรอกชื่อของคุณเพื่อเริ่มงาน"),
                const SizedBox(height: 15),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: "ชื่อคนขับ / ชื่อเล่น",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "ยกเลิก",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                onPressed: () async {
                  if (nameController.text.trim().isNotEmpty) {
                    String name = nameController.text.trim();

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('saved_driver_name', name);

                    setState(() => _driverName = name);
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  "ยืนยัน",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _listenToBusStatusRealtime() {
    FirebaseDatabase.instance.ref("GPS").onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      Map<String, String> newStatus = {};
      // ตัวแปรเสริม: เก็บสีของแต่ละคันไว้ด้วย
      Map<String, String> busColors = {};

      if (data is Map) {
        data.forEach((key, value) {
          String dName = "";
          String dColor = ""; // ตัวแปรเก็บสี

          // เช็คชั้นนอก
          if (value is Map && value.containsKey('driverName')) {
            dName = value['driverName'].toString();
            // เก็บสีด้วย
            if (value.containsKey('routeColor'))
              dColor = value['routeColor'].toString();
          }
          // เช็คชั้นใน (Nested Fix)
          else if (value is Map &&
              value.containsKey(key) &&
              value[key] is Map) {
            var inner = value[key];
            if (inner.containsKey('driverName')) {
              dName = inner['driverName'].toString();
              // เก็บสีด้วย
              if (inner.containsKey('routeColor'))
                dColor = inner['routeColor'].toString();
            }
          }

          if (dName.isNotEmpty) {
            newStatus[key.toString()] = dName;
            if (dColor.isNotEmpty)
              busColors[key.toString()] = dColor; // จำสีไว้
          }
        });
      }

      setState(() {
        _busStatus = newStatus;

        // Auto Select: ถ้ารถคันไหนเป็นชื่อเรา ให้เลือกมารอไว้เลย
        if (_driverName != null) {
          // หาว่าเราขับคันไหนอยู่
          final myBusEntry = newStatus.entries.firstWhere(
            (e) => e.value == _driverName,
            orElse: () => const MapEntry("", ""),
          );

          // ถ้าเจอรถของเรา
          if (myBusEntry.key.isNotEmpty) {
            // 1. เลือกรถให้เอง (ถ้ายังไม่ได้เลือก)
            if (_selectedBus == null) {
              _selectedBus = myBusEntry.key;
            }

            // 2. เลือกสีให้เองด้วย! (ถ้ายังไม่ได้เลือก หรือ เป็นรถคันเดิม)
            if (_selectedBus == myBusEntry.key && _selectedRoute == null) {
              String? savedColor = busColors[myBusEntry.key];
              if (savedColor != null && savedColor.isNotEmpty) {
                _selectedRoute = savedColor;
              }
            }
          }
        }
      });
    });
  }

  // --- ฟังก์ชัน 1: บันทึกงาน (Start Work / Update) ---
  void _submitData() async {
    if (_selectedBus == null || _selectedRoute == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("กรุณาเลือกข้อมูลให้ครบ")));
      return;
    }

    String? currentDriver = _busStatus[_selectedBus];
    if (currentDriver != null &&
        currentDriver.isNotEmpty &&
        currentDriver != _driverName) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("❌ เลือกไม่ได้ครับ"),
          content: Text(
            "รถคันนี้มีคนขับชื่อ '$currentDriver' ใช้งานอยู่\nกรุณาเลือกคันอื่น หรือแจ้งให้เขากด 'เลิกงาน' ก่อน",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ตกลง"),
            ),
          ],
        ),
      );
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );

      DatabaseReference refSimple = FirebaseDatabase.instance.ref(
        "GPS/$_selectedBus",
      );

      Map<String, dynamic> updateData = {
        "driverName": _driverName,
        "routeColor": _selectedRoute,
        "routeName": _getRouteName(_selectedRoute!),
        "lastUpdate": ServerValue.timestamp,
      };

      await refSimple.update(updateData);

      // --- New: Save Log for Reporting ---
      try {
        final now = DateTime.now();
        // Use YYYY-MM document ID structure or just auto-id
        await FirebaseFirestore.instance.collection('bus_operation_logs').add({
          "bus_id": _selectedBus,
          "driver_name": _driverName,
          "route_color": _selectedRoute,
          "route_name": _getRouteName(_selectedRoute!),
          "timestamp": FieldValue.serverTimestamp(),
          "year": now.year,
          "month": now.month,
          "day": now.day,
        });
      } catch (logErr) {
        print("Error logging bus operation: $logErr");
      }
      // ------------------------------------

      if (mounted) {
        // *** แก้ตรงนี้: ใช้ pushAndRemoveUntil เพื่อป้องกันจอดำ ***
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const UpBusHomePage()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ บันทึก: $_driverName ขับ $_selectedBus"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // ปิด Loading ถ้า Error
      print("Error: $e");
    }
  }

  // --- ฟังก์ชัน 2: เลิกงาน / พักรถ (Break / Finish Work) ---
  void _releaseBus() async {
    if (_selectedBus == null) return;

    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("พักเบรค / เลิกงาน?"),
            content: Text(
              "คุณต้องการเลิกขับรถ $_selectedBus ใช่หรือไม่?\nสถานะรถจะเปลี่ยนเป็น 'ว่าง'",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("ยกเลิก"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "ยืนยัน",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      ); // เพิ่ม Loading ให้ดูดีขึ้น

      DatabaseReference refSimple = FirebaseDatabase.instance.ref(
        "GPS/$_selectedBus",
      );

      await refSimple.update({
        "driverName": "",
        "routeColor": "white",
        "routeName": "ว่าง",
        "lastUpdate": ServerValue.timestamp,
      });

      if (mounted) {
        // *** แก้ตรงนี้: ใช้ pushAndRemoveUntil เพื่อป้องกันจอดำ ***
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const UpBusHomePage()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🛑 พักรถเรียบร้อย"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      print("Error releasing: $e");
    }
  }

  String _getRouteName(String colorValue) {
    var route = _routeList.firstWhere(
      (r) => r['value'] == colorValue,
      orElse: () => {},
    );
    return route['name'] ?? "";
  }

  String _formatBusName(String busId) {
    return "รถเบอร์ ${busId.split('_').last}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("เปลี่ยนสายรถบัส EV"),
        backgroundColor: Colors.purple[700],
        centerTitle: true,
      ),
      body: _driverName == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchTodaySchedule,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple[50],
                            radius: 30,
                            child: const Icon(
                              Icons.person,
                              color: Colors.purple,
                              size: 30,
                            ),
                          ),
                          title: const Text(
                            "สวัสดีคนขับ",
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          subtitle: Text(
                            _driverName!,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple[800],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.edit_note,
                              color: Colors.purple,
                            ),
                            onPressed: _showDriverNameDialog,
                            tooltip: "แก้ไขชื่อ",
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "🚌 เลือกรถที่จะขับ",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedBus,
                                hint: Text(
                                  _isLoadingSchedule
                                      ? "กำลังโหลดตารางเดินรถ..."
                                      : (_todaySchedule.isEmpty
                                            ? "ไม่มีตารางเดินรถวันนี้"
                                            : "-- กรุณาเลือกรถ --"),
                                ),
                                disabledHint: Text(
                                  _isLoadingSchedule
                                      ? "กำลังโหลดตารางเดินรถ..."
                                      : "ไม่มีรถว่างให้เลือก",
                                ),
                                isExpanded: true,
                                items: _todaySchedule.keys.map((busId) {
                                  String? currentDriver = _busStatus[busId];
                                  bool isOccupied =
                                      currentDriver != null &&
                                      currentDriver.isNotEmpty;
                                  bool isMine = currentDriver == _driverName;
                                  // String routeForBus = _todaySchedule[busId] ?? ""; // check route if needed

                                  return DropdownMenuItem<String>(
                                    value: busId,
                                    child: Row(
                                      children: [
                                        Icon(
                                          isOccupied
                                              ? (isMine
                                                    ? Icons.person_pin
                                                    : Icons.lock)
                                              : Icons.check_circle_outline,
                                          color: isOccupied
                                              ? (isMine
                                                    ? Colors.blue
                                                    : Colors.red)
                                              : Colors.green,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: _formatBusName(busId),
                                                ),
                                                TextSpan(
                                                  text: isOccupied
                                                      ? (isMine
                                                            ? " (คุณขับอยู่ ✅)"
                                                            : " ($currentDriver ❌)")
                                                      : " (ว่าง)",
                                                  style: TextStyle(
                                                    color: isOccupied
                                                        ? (isMine
                                                              ? Colors.blue
                                                              : Colors.red)
                                                        : Colors.green,
                                                    fontWeight: isOccupied
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedBus = val;
                                    // Auto-select route from schedule
                                    if (val != null &&
                                        _todaySchedule.containsKey(val)) {
                                      _selectedRoute = _todaySchedule[val];
                                    }
                                  });
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),
                          const Text(
                            "🎨 วันนี้วิ่งสายสีอะไร? (ระบบเลือกให้อัตโนมัติ)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            decoration: BoxDecoration(
                              color: Colors
                                  .grey
                                  .shade200, // Gray out to indicate read-only
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedRoute,
                                hint: const Text("-- รอเลือกเบอร์รถ --"),
                                isExpanded: true,
                                // Disable user interaction by passing null to onChanged (or valid list but ignore change? better to disable)
                                // Actually to make it look disabled but show value, onChanged must be null
                                onChanged: null,
                                icon: const Icon(
                                  Icons.lock,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                items: _routeList.map((route) {
                                  return DropdownMenuItem<String>(
                                    value: route['value'],
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: route['color'],
                                          radius: 8,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          route['name'],
                                          style: const TextStyle(
                                            color: Colors.black87,
                                          ), // Ensure visible text
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple[700],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _submitData,
                              icon: const Icon(Icons.save, color: Colors.white),
                              label: const Text(
                                "ยืนยัน / เริ่มงาน",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 15),

                          if (_selectedBus != null)
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _releaseBus,
                                icon: const Icon(
                                  Icons.stop_circle_outlined,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  "เลิกงาน / พักรถ (คืนสถานะว่าง)",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
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
            ),
    );
  }
}

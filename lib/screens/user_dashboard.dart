import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'login_page.dart';
import 'dart:convert';
import 'location_share.dart';
import 'report_missing_person.dart';
import 'safe_path_page.dart';

class UserDashboard extends StatefulWidget {
  @override
  _UserDashboardState createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  String? _selectedEvent;

  final _registerIdController = TextEditingController();
  final _attendeeNameController = TextEditingController();

  bool _showQrCode = false;

  String _qrData = '';
  String _eventName = '';
  String _assignedTime = '';
  int? _assignedGate;

  // New state variable for safety feature
  bool _isEvacActive = false;

  @override
  void dispose() {
    _registerIdController.dispose();
    _attendeeNameController.dispose();
    super.dispose();
  }

  // Real-time listener for the evacuation flag
  void _setupEvacuationListener(String eventId) {
    FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _isEvacActive = snapshot.data()?['evacuationTriggered'] ?? false;
        });
      }
    });
  }

  Future<void> _registerForEvent() async {
    if (_selectedEvent == null ||
        _registerIdController.text.isEmpty ||
        _attendeeNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    try {
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(_selectedEvent)
          .get();

      if (!eventDoc.exists) return;

      final data = eventDoc.data() as Map<String, dynamic>;

      setState(() {
        _eventName = data['name'] ?? "Event";
        _isEvacActive = data['evacuationTriggered'] ?? false;
      });

      // --- START OF YOUR ORIGINAL FIXED LOGIC ---
      final dynamic gateData = data['gates'];
      int gatesCount = 1;

      // Handle both cases: gates as a number or gates as a list of markers
      if (gateData is num) {
        gatesCount = gateData.toInt();
      } else if (gateData is List) {
        gatesCount = gateData.isNotEmpty ? gateData.length : 1;
      }
      if (gatesCount == 0) gatesCount = 1;

      final int maxAttendees = data['maxAttendees'] ?? 100;
      final String startTimeStr = data['startTime'] ?? "10:00";

      final registeredCount = await _getRegistrationCount(_selectedEvent!);
      final attendeeIndex = registeredCount + 1;

      // Calculation for Gate and Time Slot
      final double attendeesPerGateRaw = maxAttendees / gatesCount;
      final int attendeesPerGate = attendeesPerGateRaw.ceil();
      final int gateNumber = ((attendeeIndex - 1) ~/ attendeesPerGate) + 1;

      _assignedGate = gateNumber;

      // Time parsing and Slotting
      final timeParts = startTimeStr.split(':');
      final startHour = int.parse(timeParts[0]);
      final startMinute = int.parse(timeParts[1]);

      final eventStartTime = DateTime(2025, 1, 1, startHour, startMinute);
      final entryStartTime = eventStartTime.subtract(const Duration(hours: 1));

      final slotStart =
          entryStartTime.add(Duration(minutes: (attendeeIndex % 6) * 10));
      final slotEnd = slotStart.add(const Duration(minutes: 10));

      _assignedTime =
          "${slotStart.hour}:${slotStart.minute.toString().padLeft(2, '0')} - "
          "${slotEnd.hour}:${slotEnd.minute.toString().padLeft(2, '0')}";
      // --- END OF YOUR ORIGINAL FIXED LOGIC ---

      DocumentReference reg =
          await FirebaseFirestore.instance.collection("registrations").add({
        "eventId": _selectedEvent,
        "eventName": _eventName,
        "registerId": _registerIdController.text,
        "attendeeName": _attendeeNameController.text,
        "userId": FirebaseAuth.instance.currentUser!.uid,
        "assignedGate": _assignedGate,
        "assignedTime": _assignedTime,
        "checkedIn": false,
        "createdAt": DateTime.now()
      });

      setState(() {
        _qrData = jsonEncode({
          "registrationId": reg.id,
          "userId": FirebaseAuth.instance.currentUser!.uid,
          "eventId": _selectedEvent
        });
        _showQrCode = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error : $e")),
      );
    }
  }

  Future<int> _getRegistrationCount(String eventId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection("registrations")
        .where("eventId", isEqualTo: eventId)
        .get();
    return snapshot.docs.length;
  }

  void _closeQrCode() {
    setState(() {
      _showQrCode = false;
      _selectedEvent = null;
      _registerIdController.clear();
      _attendeeNameController.clear();
    });
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (context) => LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("User Dashboard"),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut)
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection("events").snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    children: [
                      // IMPROVISATION: PROACTIVE ALERT BANNER
                      if (_isEvacActive)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.warning, color: Colors.white),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "🚨 EVACUATION TRIGGERED! View safe path in the Map.",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),

                      DropdownButtonFormField<String>(
                        value: _selectedEvent,
                        decoration: const InputDecoration(
                            labelText: "Select Event",
                            border: OutlineInputBorder()),
                        items: snapshot.data!.docs.map((doc) {
                          return DropdownMenuItem(
                            value: doc.id,
                            child: Text(doc["name"]),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedEvent = val;
                          });
                          if (val != null) _setupEvacuationListener(val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _registerIdController,
                        decoration: const InputDecoration(
                            labelText: "Register ID",
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _attendeeNameController,
                        decoration: const InputDecoration(
                            labelText: "Attendee Name",
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _registerForEvent,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text("Register For Event"),
                      )
                    ],
                  ),
                ),
                if (_showQrCode) _buildTicketOverlay()
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTicketOverlay() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Event Ticket",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text("Event : $_eventName"),
                  Text("Attendee : ${_attendeeNameController.text}"),
                  Text("Gate : $_assignedGate"),
                  Text("Time : $_assignedTime"),
                  const SizedBox(height: 15),
                  QrImageView(
                    data: _qrData,
                    size: 200,
                  ),
                  const SizedBox(height: 20),

                  // IMPROVISATION: EMERGENCY EXIT MAP BUTTON
                  if (_isEvacActive)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.map, color: Colors.white),
                        label: const Text("🚨 EMERGENCY EXIT MAP"),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LocationSharePage(
                                eventId: _selectedEvent!,
                                userId: FirebaseAuth.instance.currentUser!.uid,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
                    ),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.gps_fixed),
                    label: const Text("Start Sharing Location"),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LocationSharePage(
                            eventId: _selectedEvent!,
                            userId: FirebaseAuth.instance.currentUser!.uid,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45)),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_search),
                    label: const Text("Report Missing Person"),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MissingPersonReport(
                            eventId: _selectedEvent!,
                            reporterId: FirebaseAuth.instance.currentUser!.uid,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45)),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _closeQrCode,
                    child: const Text("Close"),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import 'login_page.dart';
import 'package:newgo/screens/venue_boundary_setup.dart';
import 'package:newgo/screens/admin_heatmap_grid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'admin_missing_person.dart';

// Enum to manage the three different views in the Admin Dashboard
enum AdminView {
  addEvent,
  registeredEvents,
  scannedRegistrations,
}

class AdminDashboard extends StatefulWidget {
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _eventNameController = TextEditingController();
  final _eventDateController = TextEditingController();
  final _maxAttendeesController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _gatesController = TextEditingController();

  bool _isScanning = false;
  Map<String, dynamic>? _scannedData;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // State variable to track the currently selected tab
  AdminView _selectedView = AdminView.registeredEvents; 
  String? _scanningEventId; // Holds the ID of the event currently being scanned

  final MobileScannerController _scannerController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  // Safety constant must match the one used in venue_boundary_setup.dart
  static const double MIN_SQM_PER_PERSON = 3.0;

  @override
  void dispose() {
    _eventNameController.dispose();
    _eventDateController.dispose();
    _maxAttendeesController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _gatesController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // --- Utility Functions ---
  
  Future<void> _selectStartTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _startTime) {
      setState(() {
        _startTime = picked;
        _startTimeController.text = _formatTimeOfDay(picked);
      });
    }
  }

  Future<void> _selectEndTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );
    if (picked != null && picked != _endTime) {
      setState(() {
        _endTime = picked;
        _endTimeController.text = _formatTimeOfDay(picked);
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay timeOfDay) {
    final hour = timeOfDay.hour.toString().padLeft(2, '0');
    final minute = timeOfDay.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _calculateDuration() {
    if (_startTime != null && _endTime != null) {
      int startMinutes = _startTime!.hour * 60 + _startTime!.minute;
      int endMinutes = _endTime!.hour * 60 + _endTime!.minute;
      if (endMinutes < startMinutes) {
        endMinutes += 24 * 60;
      }
      int durationMinutes = endMinutes - startMinutes;
      int hours = durationMinutes ~/ 60;
      int minutes = durationMinutes % 60;
      return '${hours}h ${minutes}m';
    }
    return '';
  }

  Future<void> _addEvent() async {
    if (_eventNameController.text.isNotEmpty && _eventDateController.text.isNotEmpty) {
      try {
        int? maxAttendees = _maxAttendeesController.text.isNotEmpty ? int.tryParse(_maxAttendeesController.text) : null;
        int? gates = _gatesController.text.isNotEmpty ? int.tryParse(_gatesController.text) : null;

        await FirebaseFirestore.instance.collection('events').add({
          'name': _eventNameController.text,
          'date': _eventDateController.text,
          'maxAttendees': maxAttendees,
          'startTime': _startTimeController.text,
          'endTime': _endTimeController.text,
          'duration': _calculateDuration(),
          'gates': gates,
          'createdAt': DateTime.now(),
          'checkedInAttendees': 0,
        });

        _eventNameController.clear();
        _eventDateController.clear();
        _maxAttendeesController.clear();
        _startTimeController.clear();
        _endTimeController.clear();
        _gatesController.clear();
        setState(() {
          _startTime = null;
          _endTime = null;
          _selectedView = AdminView.registeredEvents; // Switch view after adding
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event added successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event name and date are required')),
      );
    }
  }

  // 🛑 MODIFIED: Takes eventId to start the scanning session
  void _startScanning(String eventId) {
    setState(() {
      _isScanning = true;
      _scannedData = null;
      _scanningEventId = eventId; // Store the ID of the event being scanned
    });
  }

  void _stopScanning() {
    setState(() {
      _isScanning = false;
      _scanningEventId = null; // Clear the scanning event ID
    });
  }

  // 🛑 MODIFIED: Verifies the ticket against the current scanning event ID
  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        try {
          Map<String, dynamic> data = jsonDecode(barcode.rawValue!);
          
          // CRITICAL SECURITY CHECK: Ensure scanned ticket belongs to the current event
          if (data['eventId'] != _scanningEventId) {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('SECURITY ALERT: Ticket does not belong to this event!'), backgroundColor: Colors.deepOrange),
            );
            _stopScanning();
            return;
          }

          setState(() {
            _scannedData = data;
            _isScanning = false;
            _selectedView = AdminView.scannedRegistrations; // Switch view after scan
          });
          _verifyRegistration(data);
          break;
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid QR code format')),
          );
        }
      }
    }
  }
  
  Future<void> _verifyRegistration(Map<String, dynamic> data) async {
    try {
      if (data.containsKey('registrationId')) {
        DocumentSnapshot regDoc = await FirebaseFirestore.instance
            .collection('registrations')
            .doc(data['registrationId'])
            .get();

        if (!regDoc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration not found in database'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        Map<String, dynamic> regData = regDoc.data() as Map<String, dynamic>;
        if (regData['checkedIn'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This QR code has already been scanned'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Valid entry granted!'),
            backgroundColor: Colors.green,
          ),
        );

        String? eventId = regDoc['eventId'];
        if (eventId != null) {
          DocumentReference eventRef = FirebaseFirestore.instance.collection('events').doc(eventId);
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            DocumentSnapshot eventSnapshot = await transaction.get(eventRef);
            if (eventSnapshot.exists) {
              int currentCount = (eventSnapshot.data() as Map<String, dynamic>)['checkedInAttendees'] ?? 0;
              transaction.update(eventRef, {'checkedInAttendees': currentCount + 1});
            }
          });
        }

        await FirebaseFirestore.instance
            .collection('registrations')
            .doc(data['registrationId'])
            .update({
          'checkedIn': true,
          'checkedInAt': DateTime.now(),
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid registration QR code'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error verifying registration: $e')),
      );
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()),
    );
  }

  // --- EVENT EDITING & SAFETY LOGIC ---

  Future<void> _recheckEventSafety(String eventId, int maxAttendees) async {
    try {
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance.collection('events').doc(eventId).get();
      final eventData = eventDoc.data() as Map<String, dynamic>?;
      
      final double venueSizeSqM = eventData?['venueSizeSqM'] as double? ?? 0.0;
      
      if (venueSizeSqM == 0.0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event updated. Capacity check skipped (Venue boundary not set).')),
        );
        return; 
      }

      final int safeCapacity = (venueSizeSqM / MIN_SQM_PER_PERSON).floor();
      String newSafetyStatus;
      
      if (maxAttendees > safeCapacity) {
        newSafetyStatus = 'CRITICAL_UNSAFE';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ WARNING: Max Attendees still exceeds Safe Capacity ($safeCapacity)!'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      } else {
        newSafetyStatus = 'SAFE';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ CAPACITY CHECK PASSED! Event is now marked SAFE.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }

      await FirebaseFirestore.instance.collection('events').doc(eventId).update({
        'safetyStatus': newSafetyStatus,
        'safeCapacity': safeCapacity,
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during safety recheck: $e')),
      );
    }
  }

  Future<void> _updateEvent(
      String eventId,
      String name,
      String date,
      String maxAttendeesStr,
      String gatesStr,
      String startTime,
      String endTime,
  ) async {
    try {
      int? maxAttendees = int.tryParse(maxAttendeesStr);
      int? gates = int.tryParse(gatesStr);
      
      await FirebaseFirestore.instance.collection('events').doc(eventId).update({
        'name': name,
        'date': date,
        'maxAttendees': maxAttendees,
        'startTime': startTime,
        'endTime': endTime,
        'gates': gates,
      });

      if (maxAttendees != null) {
        _recheckEventSafety(eventId, maxAttendees); 
      } else {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event updated successfully!')),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating event: $e')),
      );
    }
  }

  void _showEventDetails(BuildContext context, String eventId, Map<String, dynamic> eventData) {
    // Controllers pre-filled with existing data
    final editNameController = TextEditingController(text: eventData['name']);
    final editDateController = TextEditingController(text: eventData['date']);
    final editMaxAttendeesController = TextEditingController(text: eventData['maxAttendees']?.toString() ?? '');
    final editGatesController = TextEditingController(text: eventData['gates']?.toString() ?? '');
    final editStartTimeController = TextEditingController(text: eventData['startTime']);
    final editEndTimeController = TextEditingController(text: eventData['endTime']);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Edit Event Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(controller: editNameController, decoration: const InputDecoration(labelText: 'Event Name')),
                TextField(controller: editDateController, decoration: const InputDecoration(labelText: 'Event Date')),
                TextField(controller: editMaxAttendeesController, decoration: const InputDecoration(labelText: 'Max Attendees'), keyboardType: TextInputType.number),
                TextField(controller: editGatesController, decoration: const InputDecoration(labelText: 'Number of Gates'), keyboardType: TextInputType.number),
                TextField(controller: editStartTimeController, decoration: const InputDecoration(labelText: 'Start Time'), readOnly: true),
                TextField(controller: editEndTimeController, decoration: const InputDecoration(labelText: 'End Time'), readOnly: true),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop()),
            ElevatedButton(
              child: const Text('Save Changes'),
              onPressed: () {
                _updateEvent(
                  eventId,
                  editNameController.text,
                  editDateController.text,
                  editMaxAttendeesController.text,
                  editGatesController.text,
                  editStartTimeController.text,
                  editEndTimeController.text,
                );
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // --- VIEW BUILDING WIDGETS ---

  Widget _buildAddEventView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add New Event',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _eventNameController,
            decoration: const InputDecoration(
              labelText: 'Event Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _eventDateController,
            decoration: const InputDecoration(
              labelText: 'Event Date',
              border: OutlineInputBorder(),
              hintText: 'YYYY-MM-DD',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxAttendeesController,
                  decoration: const InputDecoration(
                    labelText: 'Max Attendees',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _gatesController,
                  decoration: const InputDecoration(
                    labelText: 'Number of Gates',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Start Time',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                  onTap: () => _selectStartTime(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _endTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'End Time',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.access_time),
                  ),
                  onTap: () => _selectEndTime(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_startTime != null && _endTime != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Duration: ${_calculateDuration()}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _addEvent,
            child: const Text('Add Event'),
          ),
        ],
      ),
    );
  }

  // Inside the _AdminDashboardState class in admin_dashboard.dart

Widget _buildRegisteredEventsView() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Registered Events',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return ListView.builder(
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                var eventDoc = snapshot.data!.docs[index];
                var event = eventDoc.data() as Map<String, dynamic>;
                String eventId = eventDoc.id;
                
                final safetyStatus = event['safetyStatus'] as String? ?? 'UNKNOWN';
                final safeCapacity = event['safeCapacity'] as int?;
                final isUnsafe = safetyStatus == 'CRITICAL_UNSAFE';
                
                return Card(
                  color: isUnsafe ? Colors.red.shade50 : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                event['name'] ?? 'Unnamed Event',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isUnsafe ? Colors.red.shade900 : Colors.black,
                                ),
                              ),
                            ),
                            if (isUnsafe)
                              Tooltip(
                                message: 'CRITICAL: Max Attendees (${event['maxAttendees']}) exceeds Safe Capacity ($safeCapacity).',
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning, color: Colors.red, size: 24),
                                    const SizedBox(width: 4),
                                    Text('UNSAFE!', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            Row(
                              children: [
                                // Event-Specific Scan Button
                                IconButton(
                                  icon: const Icon(Icons.qr_code_scanner, color: Colors.green),
                                  tooltip: 'Scan Ticket for this Event',
                                  onPressed: () => _startScanning(eventId), // Pass eventId to start scan
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  tooltip: 'Edit Event',
                                  onPressed: () => _showEventDetails(context, eventId, event),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.map, color: Colors.green),
                                  tooltip: 'Set Venue Boundary',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => VenueBoundarySetup(eventId: eventId),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.show_chart, color: Colors.red),
                                  tooltip: 'View Live Heatmap',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AdminHeatmapGridPage(eventId: eventId),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.person_search, color: Colors.orange),
                                  tooltip: 'Missing Persons',
                                  onPressed: () {
                                    Navigator.push(
                                       context,
                                      MaterialPageRoute(
                                       builder: (context) => AdminMissingPersonsPage(eventId: eventId),
                                      ),
                                    );
                                 },
                                ),
                                
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Date: ${event['date'] ?? 'No date set'}'),
                        if (event['startTime'] != null && event['endTime'] != null) ...[
                          const SizedBox(height: 2),
                          Text('Time: ${event['startTime']} - ${event['endTime']} (${event['duration'] ?? 'N/A'})'),
                        ],
                        const SizedBox(height: 2),
                        if (safeCapacity != null)
                          Text('Safe Capacity: $safeCapacity | Status: $safetyStatus',
                            style: TextStyle(
                              fontSize: 12,
                              color: isUnsafe ? Colors.red.shade700 : Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Attendees: ${event['checkedInAttendees'] ?? 0}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            if (event['maxAttendees'] != null) ...[
                              Text(' / ${event['maxAttendees']}'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: event['maxAttendees'] > 0
                                      ? ((event['checkedInAttendees'] ?? 0) / event['maxAttendees']).clamp(0.0, 1.0)
                                      : 0.0,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    (event['checkedInAttendees'] ?? 0) >= event['maxAttendees']
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}
  Widget _buildScannedRegistrationsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Scanned Registrations',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        
        // Removed the general 'Scan QR' button since it's now per-event
        
        const SizedBox(height: 32),

        // Scanned Data Display
        if (_scannedData != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last Scanned Registration',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Event: ${_scannedData!['eventName'] ?? 'Unknown'}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Registration ID: ${_scannedData!['registrationId'] ?? 'Unknown'}'),
                        const SizedBox(height: 4),
                        Text('Attendee: ${_scannedData!['attendeeName'] ?? 'Unknown'}'),
                        const SizedBox(height: 4),
                        Text('User ID: ${_scannedData!['userId'] ?? 'Unknown'}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 🛑 FIX: This entire block is now wrapped in an 'if' conditional
        if (_scannedData == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text("Ready to scan. Select an event from 'Registered Events' to start verification."),
          ),
      ],
    );
  }

  Widget _buildCurrentView() {
    switch (_selectedView) {
      case AdminView.addEvent:
        return _buildAddEventView();
      case AdminView.registeredEvents:
        return _buildRegisteredEventsView();
      case AdminView.scannedRegistrations:
        return _buildScannedRegistrationsView();
      default:
        return _buildRegisteredEventsView();
    }
  }
  
  // 🛑 FIX: The function signature was missing the context argument which caused the error on line 506
  Widget _buildNavigationBar() {
    const double iconSize = 40.0;
    const double borderRadius = 12.0;

    const Map<AdminView, Map<String, dynamic>> navItems = {
      AdminView.registeredEvents: {
        'label': 'Events & Monitor',
        'icon': Icons.event_note,
        'color': Colors.blue,
      },
      AdminView.addEvent: {
        'label': 'Add an Event',
        'icon': Icons.add_circle,
        'color': Colors.orange,
      },
      AdminView.scannedRegistrations: {
        'label': 'Scan Records',
        'icon': Icons.list_alt,
        'color': Colors.green,
      },
    };

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: navItems.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10.0,
          mainAxisSpacing: 10.0,
          childAspectRatio: 1.0, // Ensures square buttons
        ),
        itemBuilder: (context, index) {
          final view = navItems.keys.elementAt(index);
          final item = navItems[view]!;
          final isSelected = view == _selectedView;
          
          return GestureDetector(
            onTap: () => setState(() => _selectedView = view),
            child: Card(
              elevation: isSelected ? 8 : 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
                side: isSelected 
                    ? BorderSide(color: item['color'] as Color, width: 3)
                    : BorderSide.none,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  color: isSelected ? item['color'].withOpacity(0.1) : Colors.white,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item['icon'] as IconData,
                      size: iconSize,
                      color: item['color'] as Color,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['label'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: item['color'] as Color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
  
  // --- MAIN BUILD METHOD ---
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // NAVIGATION BAR
              _buildNavigationBar(),
              
              const Divider(height: 1, thickness: 1),

              // DISPLAY SELECTED VIEW
              Expanded(
                child: _buildCurrentView(),
              ),
            ],
          ),

          // FULL-SCREEN QR SCANNER OVERLAY
          if (_isScanning)
            Positioned.fill(
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  ),
                  Positioned(
                    top: 20,
                    right: 20,
                    child: FloatingActionButton(
                      onPressed: _stopScanning,
                      child: const Icon(Icons.close),
                      mini: true,
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        // Displaying the name of the event being scanned for context
                        'Scanning Ticket for ${_scanningEventId}', 
                        style: TextStyle(
                          color: Colors.white,
                          backgroundColor: Colors.black54,
                          fontSize: 16,
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
    );
  }
}
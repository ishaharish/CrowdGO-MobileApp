import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Ensure these files exist in your project
import 'venue_boundary_setup.dart'; 

class EventCreationScreen extends StatefulWidget {
  @override
  State<EventCreationScreen> createState() => _EventCreationScreenState();
}

class _EventCreationScreenState extends State<EventCreationScreen> {
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();
  String? eventId; 
  bool _isCreating = false;

  // STEP 1: Create the event document to get a valid eventId
  Future<void> _initializeEvent() async {
    if (_nameController.text.isEmpty || _capacityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter name and capacity first')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // Create document in 'events' collection
      DocumentReference ref = await FirebaseFirestore.instance.collection('events').add({
        'name': _nameController.text,
        'safeCapacity': int.parse(_capacityController.text),
        'safetyStatus': 'SAFE', // Initial status
        'evacuationTriggered': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        eventId = ref.id; // Assign the new Firestore ID
        _isCreating = false;
      });
    } catch (e) {
      setState(() => _isCreating = false);
      print("Error creating event: $e");
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create New Event')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (eventId == null) ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'Event Name', border: OutlineInputBorder()),
              ),
              SizedBox(height: 10),
              TextField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Expected Capacity', border: OutlineInputBorder()),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isCreating ? null : _initializeEvent,
                child: _isCreating ? CircularProgressIndicator() : Text('Setup Venue Boundary'),
              ),
            ] else ...[
              // Once eventId is generated, show the Map Setup
              Expanded(
                child: VenueBoundarySetup(
                  eventId: eventId!,
                  onCompleted: () {
                    Navigator.pop(context); // Go back when finished
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
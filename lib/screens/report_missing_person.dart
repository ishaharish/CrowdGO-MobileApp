import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart' as loc;

class MissingPersonReport extends StatefulWidget {
  final String eventId;
  final String reporterId;

  const MissingPersonReport({Key? key, required this.eventId, required this.reporterId}) : super(key: key);

  @override
  State<MissingPersonReport> createState() => _MissingPersonReportState();
}

class _MissingPersonReportState extends State<MissingPersonReport> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _healthController = TextEditingController();
  final TextEditingController _lastSeenController = TextEditingController();
  final TextEditingController _clothesController = TextEditingController();

  File? _image;
  bool _isSubmitting = false;

  Future<void> _pickImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // DRIVER FIX: Aggressive compression to stay under 1MB Firestore limit
        maxWidth: 300, 
        maxHeight: 300,
        imageQuality: 20, 
      );
      if (pickedFile != null) {
        setState(() => _image = File(pickedFile.path));
      }
    } catch (e) {
      _showSnackBar("Error picking image: $e");
    }
  }

  Future<void> _submitReport() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar("Please enter the person's name");
      return;
    }

    setState(() => _isSubmitting = true);

    double? lastSeenLat;
    double? lastSeenLng;
    try {
      loc.Location location = loc.Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
      }
      if (serviceEnabled) {
        loc.PermissionStatus permissionGranted = await location.hasPermission();
        if (permissionGranted == loc.PermissionStatus.denied) {
          permissionGranted = await location.requestPermission();
        }
        if (permissionGranted == loc.PermissionStatus.granted || permissionGranted == loc.PermissionStatus.grantedLimited) {
          // Set timeout for fetching location to avoid hanging too long
          final locData = await location.getLocation().timeout(const Duration(seconds: 10));
          lastSeenLat = locData.latitude;
          lastSeenLng = locData.longitude;
        }
      }
    } catch (e) {
      debugPrint("Error fetching exact location for report: $e");
    }

    try {
      String? base64Image;

      if (_image != null) {
        final bytes = await _image!.readAsBytes();
        // Safety check: only encode if under a safe limit
        if (bytes.length < 800000) {
          base64Image = base64Encode(bytes);
        } else {
          debugPrint("Image too large, skipping encoded string");
        }
      }

      await FirebaseFirestore.instance.collection("missing_person_reports").add({
        "eventId": widget.eventId,
        "reporterId": widget.reporterId,
        "name": _nameController.text.trim(),
        "healthIssues": _healthController.text.trim(),
        "lastSeenLocation": _lastSeenController.text.trim(),
        "lastSeenLatitude": lastSeenLat,
        "lastSeenLongitude": lastSeenLng,
        "wornClothes": _clothesController.text.trim(),
        "photoBase64": base64Image, 
        "status": "missing",
        "reportedAt": Timestamp.now(),
      });

      if (mounted) {
        _showSnackBar("Report Submitted Successfully!");
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnackBar("Submission Error: Check image size or fields");
      debugPrint("Firestore Error: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Report Missing Person")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400, width: 2),
                ),
                child: _image != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_image!, fit: BoxFit.cover),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 50, color: Colors.grey),
                          SizedBox(height: 8),
                          Text("TAP TO ADD PHOTO", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _clothesController, decoration: const InputDecoration(labelText: "Worn Clothes (e.g. Red Shirt)", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _lastSeenController, decoration: const InputDecoration(labelText: "Last Seen Point", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _healthController, decoration: const InputDecoration(labelText: "Health Issues", border: OutlineInputBorder())),
            const SizedBox(height: 24),
            _isSubmitting
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submitReport,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text("SUBMIT EMERGENCY REPORT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
          ],
        ),
      ),
    );
  }
}
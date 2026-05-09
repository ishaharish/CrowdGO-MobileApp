import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AdminMissingPersonsPage extends StatelessWidget {
  final String eventId;
  const AdminMissingPersonsPage({super.key, required this.eventId});

  // Helper to show the image in a large dialog
  void _showLargeImage(BuildContext context, String base64String, String name) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(name),
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            Image.memory(
              base64Decode(base64String),
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showLocationMapDialog(BuildContext context, double lat, double lng, String name) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: double.infinity,
            height: 400,
            child: Column(
              children: [
                AppBar(
                  title: Text(name),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 17,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: "com.example.newgo",
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(lat, lng),
                            width: 60,
                            height: 60,
                            child: const Icon(Icons.location_on, color: Colors.red, size: 50),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Missing Person Management"),
        backgroundColor: Colors.orange.shade800,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("missing_person_reports")
            .where("eventId", isEqualTo: eventId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final reports = snapshot.data!.docs;
          if (reports.isEmpty) return const Center(child: Text("No active reports found."));

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final doc = reports[index];
              final data = doc.data() as Map<String, dynamic>;
              final bool isFound = data["status"] == "found";

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 4,
                color: isFound ? Colors.green.shade50 : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: isFound ? Colors.green : Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // CLICKABLE PHOTO
                          GestureDetector(
                            onTap: data["photoBase64"] != null 
                                ? () => _showLargeImage(context, data["photoBase64"], data["name"] ?? "Unknown")
                                : null,
                            child: Hero(
                              tag: doc.id,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: data["photoBase64"] != null
                                    ? Image.memory(
                                        base64Decode(data["photoBase64"]),
                                        width: 100, height: 100, fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 100, height: 100, color: Colors.grey[300],
                                        child: const Icon(Icons.person, size: 50),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data["name"] ?? "Unknown",
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isFound ? Colors.green : Colors.red,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    isFound ? "SAFE / FOUND" : "SEARCHING",
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text("Last Seen: ${data["lastSeenLocation"] ?? 'N/A'}", style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 25),
                      // CLOTHES & HEALTH DETAILS
                      Row(
                        children: [
                          const Icon(Icons.checkroom, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(child: Text("Wearing: ${data["wornClothes"] ?? 'No description'}")),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.medical_services, size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(child: Text("Health: ${data["healthIssues"] ?? 'None'}")),
                        ],
                      ),
                      const SizedBox(height: 15),
                      // VIEW LAST SEEN POINT BUTTON
                      if (data["lastSeenLatitude"] != null && data["lastSeenLongitude"] != null)
                        ElevatedButton.icon(
                          onPressed: () => _showLocationMapDialog(
                            context,
                            (data["lastSeenLatitude"] as num).toDouble(),
                            (data["lastSeenLongitude"] as num).toDouble(),
                            data["name"] ?? "Unknown",
                          ),
                          icon: const Icon(Icons.map),
                          label: const Text("VIEW LAST SEEN ON MAP"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 45),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      if (data["lastSeenLatitude"] != null && data["lastSeenLongitude"] != null && !isFound)
                        const SizedBox(height: 10),
                      // THE FOUND BUTTON
                      if (!isFound)
                        ElevatedButton.icon(
                          onPressed: () => _markAsFound(doc.id),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text("MARK AS FOUND"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 45),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _markAsFound(String docId) async {
    await FirebaseFirestore.instance
        .collection("missing_person_reports")
        .doc(docId)
        .update({"status": "found"});
  }
}
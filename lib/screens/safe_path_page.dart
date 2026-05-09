import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SafePathPage extends StatefulWidget {
  final String eventId;
  const SafePathPage({super.key, required this.eventId});

  @override
  State<SafePathPage> createState() => _SafePathPageState();
}

class _SafePathPageState extends State<SafePathPage> {
  final MapController _mapController = MapController();

  // SCMS Venue Coordinates (Approximate based on your screenshot)
  static const LatLng _venueCenter = LatLng(10.2705, 76.4018);
  static const LatLng _userLocation = LatLng(10.2710, 76.4015); // In front of Academic Block
  static const LatLng _exitGate = LatLng(10.2690, 76.4010);    // Main Gate area

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🚨 EMERGENCY EXIT"),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _venueCenter,
          initialZoom: 17.5, // High zoom to see the campus buildings clearly
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all, // ENABLE ZOOMING AND PINCHING
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.newgo',
          ),
          
          // --- THE ACCURATE PATH ---
          PolylineLayer(
            polylines: [
              Polyline(
                points: [
                  _userLocation,
                  const LatLng(10.2700, 76.4013), // Mid-point on campus road
                  _exitGate,
                ],
                color: Colors.red,
                strokeWidth: 6.0,
                isDotted: true,
                borderColor: Colors.white,
                borderStrokeWidth: 2.0,
              ),
            ],
          ),

          // --- THE MARKERS ---
          MarkerLayer(
            markers: [
              // User Marker
              const Marker(
                point: _userLocation,
                width: 80,
                height: 80,
                child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
              ),
              // Exit Marker
              const Marker(
                point: _exitGate,
                width: 80,
                height: 80,
                child: Column(
                  children: [
                    Text("EXIT", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, backgroundColor: Colors.white)),
                    Icon(Icons.door_front_door, color: Colors.green, size: 40),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        onPressed: () {
          // Snap back to user if they get lost on the map
          _mapController.move(_userLocation, 17.5);
        },
        child: const Icon(Icons.my_location, color: Colors.blue),
      ),
    );
  }
}
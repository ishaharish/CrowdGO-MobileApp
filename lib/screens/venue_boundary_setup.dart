import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;

class VenueBoundarySetup extends StatefulWidget {
  final String eventId;

  const VenueBoundarySetup({super.key, required this.eventId});

  @override
  State<VenueBoundarySetup> createState() => _VenueBoundarySetupState();
}

class _VenueBoundarySetupState extends State<VenueBoundarySetup> {
  List<LatLng> boundaryPoints = [];
  List<Map<String, dynamic>> gates = [];

  bool isAddingGate = false;
  bool isSaving = false;
  bool isLoading = true;

  static const double MIN_SQM_PER_PERSON = 3.0;

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVenueData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVenueData() async {
    setState(() => isLoading = true);

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        if (data['venuePolygon'] != null) {
          boundaryPoints = (data['venuePolygon'] as List)
              .map((p) => LatLng(
                    (p['latitude'] as num).toDouble(),
                    (p['longitude'] as num).toDouble(),
                  ))
              .toList();
        }

        if (data['gates'] != null) {
          gates = List<Map<String, dynamic>>.from(data['gates']);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading venue: $e')));
    }

    setState(() => isLoading = false);
  }

  Future<void> _searchAndMoveMap(String query) async {
    if (query.isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(query);

      if (locations.isNotEmpty) {
        LatLng newCenter =
            LatLng(locations.first.latitude, locations.first.longitude);

        _mapController.move(newCenter, 18);
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Location not found')));
    }
  }

  double _calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0.0;

    const double radius = 6378137.0;
    double area = 0.0;

    for (int i = 0; i < points.length; i++) {
      LatLng p1 = points[i];
      LatLng p2 = points[(i + 1) % points.length];

      double radLat1 = p1.latitude * math.pi / 180;
      double radLat2 = p2.latitude * math.pi / 180;
      double radLon1 = p1.longitude * math.pi / 180;
      double radLon2 = p2.longitude * math.pi / 180;

      area += (radLon2 - radLon1) *
          (2 + math.sin(radLat1) + math.sin(radLat2));
    }

    return (area.abs() * radius * radius / 2.0);
  }

  Future<void> _saveToFirestore() async {
    if (boundaryPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Define venue boundary first')));
      return;
    }

    setState(() => isSaving = true);

    final area = _calculatePolygonArea(boundaryPoints);

    try {
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();

      final eventData = eventDoc.data() as Map<String, dynamic>?;

      final int maxAttendees = eventData?['maxAttendees'] ?? 0;

      final int safeCapacity = (area / MIN_SQM_PER_PERSON).floor();

      String status =
          (maxAttendees > safeCapacity) ? 'CRITICAL_UNSAFE' : 'SAFE';

      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .set({
        'venuePolygon': boundaryPoints
            .map((p) => {
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
            .toList(),
        'venueSizeSqM': area,
        'gates': gates,
        'safeCapacity': safeCapacity,
        'safetyStatus': status,
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 'SAFE'
            ? 'Saved! Capacity is safe.'
            : 'Saved! WARNING: Venue too small for $maxAttendees people'),
        backgroundColor: status == 'SAFE' ? Colors.green : Colors.red,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save error: $e')));
    }

    setState(() => isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Venue Setup')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search location',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () =>
                            _searchAndMoveMap(_searchController.text),
                      ),
                    ),
                    onSubmitted: _searchAndMoveMap,
                  ),
                ),

                _buildControlRow(),

                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: boundaryPoints.isNotEmpty
                          ? boundaryPoints.first
                          : const LatLng(10.2711, 76.4014),
                      initialZoom: 18,
                      maxZoom: 19,
                      onTap: (tapPosition, latlng) {
                        setState(() {
                          if (isAddingGate) {
                            gates.add({
                              'latitude': latlng.latitude,
                              'longitude': latlng.longitude,
                              'name': 'Gate ${gates.length + 1}'
                            });
                          } else {
                            boundaryPoints.add(latlng);
                          }
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                        userAgentPackageName: "com.example.newgo",
                      ),

                      if (boundaryPoints.isNotEmpty)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: boundaryPoints,
                              borderColor: Colors.blue,
                              borderStrokeWidth: 3,
                              color: Colors.blue.withOpacity(0.3),
                            )
                          ],
                        ),

                      MarkerLayer(
                        markers: [
                          ...boundaryPoints.map(
                            (p) => Marker(
                              width: 20,
                              height: 20,
                              point: p,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    boundaryPoints.remove(p);
                                  });
                                },
                                child: const Icon(
                                  Icons.circle,
                                  color: Colors.blue,
                                  size: 12,
                                ),
                              ),
                            ),
                          ),

                          ...gates.map(
                            (g) => Marker(
                              width: 40,
                              height: 40,
                              point: LatLng(
                                  g['latitude'], g['longitude']),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    gates.remove(g);
                                  });
                                },
                                child: const Icon(
                                  Icons.door_front_door,
                                  color: Colors.green,
                                  size: 30,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildControlRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Switch(
            value: isAddingGate,
            onChanged: (val) {
              setState(() {
                isAddingGate = val;
              });
            },
          ),
          Text(isAddingGate
              ? "Mode: Adding Gates"
              : "Mode: Adding Boundary"),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: () {
              setState(() {
                boundaryPoints.clear();
                gates.clear();
              });
            },
          ),
          ElevatedButton(
            onPressed: isSaving ? null : _saveToFirestore,
            child: isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Setup'),
          ),
        ],
      ),
    );
  }
}

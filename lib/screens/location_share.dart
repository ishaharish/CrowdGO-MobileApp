import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:math';

import 'package:newgo/utils/graph_models.dart';
import 'package:newgo/utils/a_star_pathfinder.dart';

class LocationSharePage extends StatefulWidget {
  final String eventId;
  final String userId;

  const LocationSharePage({
    required this.eventId,
    required this.userId,
    super.key,
  });

  @override
  State<LocationSharePage> createState() => _LocationSharePageState();
}

class _LocationSharePageState extends State<LocationSharePage> {
  final loc.Location location = loc.Location();
  final MapController _mapController = MapController();
  bool _sharing = false;
  LatLng? _currentLocation;

  StreamSubscription? _locationSubscription;

  // Point-in-polygon algorithm (Ray-casting)
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;
    bool isInside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].longitude > point.longitude) != (polygon[j].longitude > point.longitude) &&
          (point.latitude <
              (polygon[j].latitude - polygon[i].latitude) *
                      (point.longitude - polygon[i].longitude) /
                      (polygon[j].longitude - polygon[i].longitude) +
                  polygon[i].latitude)) {
        isInside = !isInside;
      }
      j = i;
    }
    return isInside;
  }

  @override
  void initState() {
    super.initState();
    _startLocationService();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocationService() async {
    bool serviceEnabled = await location.serviceEnabled();

    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    loc.PermissionStatus permissionGranted = await location.hasPermission();

    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) return;
    }

    await location.changeSettings(
      interval: 5000,
      accuracy: loc.LocationAccuracy.high,
    );

    setState(() {
      _sharing = true;
    });

    _locationSubscription =
        location.onLocationChanged.listen((loc.LocationData locData) async {
      if (_sharing && locData.latitude != null && locData.longitude != null) {
        final currentPos = LatLng(locData.latitude!, locData.longitude!);

        setState(() {
          _currentLocation = currentPos;
        });

        _mapController.move(currentPos, 17);

        await FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventId)
            .collection('locations')
            .doc(widget.userId)
            .set({
          'latitude': locData.latitude,
          'longitude': locData.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_sharing) {
      return Scaffold(
        body: Center(
          child: ElevatedButton.icon(
            onPressed: _startLocationService,
            icon: const Icon(Icons.gps_fixed),
            label: const Text('Start Sharing Location'),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final eventData = snapshot.data!.data() as Map<String, dynamic>? ?? {};

        final bool evacuationTriggered =
            eventData['evacuationTriggered'] == true;

        final List polygonData = eventData['venuePolygon'] ?? [];

        final List<LatLng> boundaryPoints = polygonData.map((p) {
          return LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          );
        }).toList();

        final List gateData = eventData['gates'] ?? [];

        final List<Marker> gateMarkers = gateData.map((g) {
          return Marker(
            point: LatLng(
              (g['latitude'] as num).toDouble(),
              (g['longitude'] as num).toDouble(),
            ),
            width: 40,
            height: 40,
            child: const Icon(
              Icons.door_front_door,
              color: Colors.green,
              size: 30,
            ),
          );
        }).toList();

        return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('events')
                .doc(widget.eventId)
                .collection('locations')
                .snapshots(),
            builder: (context, locSnapshot) {
              if (!locSnapshot.hasData) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }

              List<LatLng> personalizedPath = [];

              if (evacuationTriggered &&
                  _currentLocation != null &&
                  boundaryPoints.isNotEmpty) {
                final positions = locSnapshot.data!.docs.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return LatLng(d['latitude'], d['longitude']);
                }).toList();

                print("DEBUG: Evacuation triggered: $evacuationTriggered");
                print("DEBUG: Current Location: $_currentLocation");
                print("DEBUG: Boundary Points: ${boundaryPoints.length}");

                final minLat =
                    boundaryPoints.map((p) => p.latitude).reduce(min);
                final maxLat =
                    boundaryPoints.map((p) => p.latitude).reduce(max);
                final minLng =
                    boundaryPoints.map((p) => p.longitude).reduce(min);
                final maxLng =
                    boundaryPoints.map((p) => p.longitude).reduce(max);

                final latStep = (maxLat - minLat) / 10;
                final lngStep = (maxLng - minLng) / 10;

                final venueSizeSqM =
                    (eventData['venueSizeSqM'] as num?)?.toDouble() ?? 1.0;
                final cellArea = venueSizeSqM / 100;

                List<List<int>> cellCounts =
                    List.generate(10, (_) => List.filled(10, 0));
                for (final pt in positions) {
                  if (pt.latitude >= minLat &&
                      pt.latitude <= maxLat &&
                      pt.longitude >= minLng &&
                      pt.longitude <= maxLng) {
                    int r =
                        ((pt.latitude - minLat) / latStep).floor().clamp(0, 9);
                    int c =
                        ((pt.longitude - minLng) / lngStep).floor().clamp(0, 9);
                    cellCounts[r][c]++;
                  }
                }

                List<GraphNode> nodes = [];
                GraphNode? startNode;
                // Clamp user coordinates to the nearest grid cell if they are just outside
                int userR = ((_currentLocation!.latitude - minLat) / latStep)
                    .floor()
                    .clamp(0, 9);
                int userC = ((_currentLocation!.longitude - minLng) / lngStep)
                    .floor()
                    .clamp(0, 9);

                for (int r = 0; r < 10; r++) {
                  for (int c = 0; c < 10; c++) {
                    double density = cellArea > 0
                        ? (cellCounts[r][c] / cellArea).toDouble()
                        : 0.0;
                    final lat = minLat + r * latStep + latStep / 2;
                    final lng = minLng + c * lngStep + lngStep / 2;
                    final cellCenter = LatLng(lat, lng);

                    // Only add nodes that actually fall inside the venue boundaries
                    if (_isPointInPolygon(cellCenter, boundaryPoints)) {
                      final node = GraphNode("$r,$c", cellCenter, density);
                      nodes.add(node);
                      if (r == userR && c == userC) {
                        startNode = node;
                      }
                    }
                  }
                }

                // If user is outside venue but needs path, connect them to nearest internal node
                if (startNode == null && nodes.isNotEmpty) {
                  double minDist = double.infinity;
                  final distCalc = const Distance();
                  for (var node in nodes) {
                    double dist = distCalc.as(
                        LengthUnit.Meter, _currentLocation!, node.point);
                    if (dist < minDist) {
                      minDist = dist;
                      startNode = node;
                    }
                  }
                  print(
                      "DEBUG: User was out of bounds! Snapped to nearest node: ${startNode?.id}");
                } else {
                  print("DEBUG: User mapped to node: ${startNode?.id}");
                }

                final exitGates = gateData
                    .map((g) => ExitGate(
                        g['name'] ?? 'Gate',
                        LatLng((g['latitude'] as num).toDouble(),
                            (g['longitude'] as num).toDouble())))
                    .toList();

                if (startNode != null && exitGates.isNotEmpty) {
                  // Evaluate the BEST path across ALL individual gates using A* or Dijkstra
                  PathResult? absoluteBestResult;
                  ExitGate? targetGateForBestPath;

                  final distCalc = const Distance();

                  for (var specificGate in exitGates) {
                    // 1. Find the nearest grid node to this specific exit gate
                    GraphNode? nearestGateNode;
                    double minGateDist = double.infinity;
                    for (var node in nodes) {
                      double dist = distCalc.as(LengthUnit.Meter, specificGate.point, node.point);
                      if (dist < minGateDist) {
                        minGateDist = dist;
                        nearestGateNode = node;
                      }
                    }

                    if (nearestGateNode != null) {
                      // 2. Pass the start node and target node so A* calculates explicitly to IT
                      //    Setting useDijkstra: false uses A* with distance heuristics. 
                      //    Setting useDijkstra: true uses Dijkstra's perfect shortest-path strategy.
                      //    The algorithm internally defaults to A* based heuristic.
                      final result = AStarPathfinder()
                          .findSafestPath(startNode, nearestGateNode, nodes, useDijkstra: false);

                      if (result.path.isNotEmpty) {
                        if (absoluteBestResult == null ||
                            result.totalCost < absoluteBestResult.totalCost) {
                          absoluteBestResult = result;
                          targetGateForBestPath = specificGate;
                        }
                      }
                    }
                  }

                  if (absoluteBestResult != null &&
                      absoluteBestResult.path.isNotEmpty) {
                    print(
                        "DEBUG: Found shortest path to gate ${targetGateForBestPath?.name} with cost ${absoluteBestResult.totalCost}");
                    personalizedPath = [
                      _currentLocation!
                    ]; // Connect user directly to path
                    personalizedPath.addAll(absoluteBestResult.path);

                    // Connect the end of the grid path exactly to the actual nearest gate coordinate
                    if (targetGateForBestPath != null) {
                      personalizedPath.add(targetGateForBestPath.point);
                    }
                  } else {
                    print("DEBUG: absoluteBestResult was null or empty!");
                  }
                } else {
                  print(
                      "DEBUG: startNode is null (${startNode == null}) or exitGates is empty (${exitGates.isEmpty})");
                }
              }

              return Scaffold(
                appBar: AppBar(
                  title: Text(personalizedPath.isNotEmpty
                      ? '🚨 EMERGENCY EXIT'
                      : 'Live Map'),
                  backgroundColor: personalizedPath.isNotEmpty
                      ? Colors.red.shade900
                      : Colors.blue,
                ),
                body: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _currentLocation ?? const LatLng(10.2711, 76.4014),
                    initialZoom: 16,
                    maxZoom: 19,
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
                            borderColor: Colors.blueAccent,
                            borderStrokeWidth: 3,
                            color: Colors.blue.withOpacity(0.05),
                          ),
                        ],
                      ),
                    if (personalizedPath.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: personalizedPath,
                            strokeWidth: 6,
                            color: Colors.purple,
                            isDotted: true,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        ...gateMarkers,
                        if (_currentLocation != null)
                          Marker(
                            point: _currentLocation!,
                            width: 80,
                            height: 80,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                        if (personalizedPath.isNotEmpty)
                          Marker(
                            point: personalizedPath.last,
                            width: 60,
                            height: 60,
                            child: const Icon(
                              Icons.stars,
                              color: Colors.orange,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                floatingActionButton: FloatingActionButton(
                  backgroundColor: Colors.white,
                  onPressed: () {
                    if (_currentLocation != null) {
                      _mapController.move(_currentLocation!, 17);
                    }
                  },
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
              );
            });
      },
    );
  }
}

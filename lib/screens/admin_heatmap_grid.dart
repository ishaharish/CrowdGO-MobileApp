import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

// Import the utility files
import 'package:newgo/utils/graph_models.dart';
import 'package:newgo/utils/a_star_pathfinder.dart';

class AdminHeatmapGridPage extends StatefulWidget {
  final String eventId;
  const AdminHeatmapGridPage({super.key, required this.eventId});

  @override
  State<AdminHeatmapGridPage> createState() => _AdminHeatmapGridPageState();
}

class _AdminHeatmapGridPageState extends State<AdminHeatmapGridPage> {

  static const int gridRows = 10;
  static const int gridCols = 10;

  static const double safeThreshold = 0.15;
  static const double moderateThreshold = 0.25;
  static const double seriousThreshold = 0.40;
  static const double criticalThreshold = 0.40;

  double _maxDensity = 0.0;
  double _totalDistance = 0.0;

  bool _evacuationTriggered = false;
  List<LatLng> _safestPath = [];

  Color getDensityColor(double density) {
    if (density < safeThreshold) {
      return Colors.green.withOpacity(0.6);
    } else if (density < moderateThreshold) {
      return Colors.yellow.withOpacity(0.7);
    } else if (density < seriousThreshold) {
      return Colors.orange.withOpacity(0.8);
    } else {
      return Colors.red.withOpacity(0.85);
    }
  }

  Widget _buildStatusPanel(double maxDensity, double limit) {
    String statusTitle;
    Color statusColor;

    if (_evacuationTriggered) {
      statusTitle = "EMERGENCY: EVACUATION ACTIVE (${maxDensity.toStringAsFixed(2)})";
      statusColor = Colors.red.shade700;
    } else if (maxDensity >= criticalThreshold) {
      statusTitle = "CRITICAL: MAX DENSITY EXCEEDED (${maxDensity.toStringAsFixed(2)})";
      statusColor = Colors.red;
    } else if (maxDensity >= moderateThreshold) {
      statusTitle = "WARNING: HIGH DENSITY ZONE (${maxDensity.toStringAsFixed(2)})";
      statusColor = Colors.orange;
    } else {
      statusTitle = "Status: Safe (Max Density: ${maxDensity.toStringAsFixed(2)})";
      statusColor = Colors.green;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            "Limit: ${limit.toStringAsFixed(2)} persons/sqm",
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerEvacuation(
      String eventId,
      List<List<int>> cellCounts,
      double venueSizeSqM,
      List<LatLng> venuePolygon) async {

    final minLat = venuePolygon.map((p) => p.latitude).reduce(min);
    final maxLat = venuePolygon.map((p) => p.latitude).reduce(max);
    final minLng = venuePolygon.map((p) => p.longitude).reduce(min);
    final maxLng = venuePolygon.map((p) => p.longitude).reduce(max);

    final latStep = (maxLat - minLat) / gridRows;
    final lngStep = (maxLng - minLng) / gridCols;

    final cellArea = venueSizeSqM / (gridRows * gridCols);

    int maxCount = 0;
    int startRow = -1;
    int startCol = -1;

    for (int r = 0; r < gridRows; r++) {
      for (int c = 0; c < gridCols; c++) {
        if (cellCounts[r][c] > maxCount) {
          maxCount = cellCounts[r][c];
          startRow = r;
          startCol = c;
        }
      }
    }

    if (maxCount == 0) return;

    final eventDoc = await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .get();

    final gatesData = eventDoc.data()?['gates'] as List? ?? [];

    final exitGates = gatesData
        .map((g) => ExitGate(g['name'], LatLng(g['latitude'], g['longitude'])))
        .toList();

    if (exitGates.isEmpty) return;

    List<GraphNode> nodes = [];
    GraphNode? startNode;

    for (int r = 0; r < gridRows; r++) {
      for (int c = 0; c < gridCols; c++) {

        final double density =
            cellArea > 0 ? (cellCounts[r][c] / cellArea).toDouble() : 0.0;

        final lat = minLat + r * latStep + latStep / 2;
        final lng = minLng + c * lngStep + lngStep / 2;

        final node = GraphNode("$r,$c", LatLng(lat, lng), density);

        nodes.add(node);

        if (r == startRow && c == startCol) {
          startNode = node;
        }
      }
    }

    if (startNode == null) return;

    PathResult? absoluteBestResult;
    final distCalc = const Distance();

    for (var specificGate in exitGates) {
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
        final tempResult = AStarPathfinder().findSafestPath(startNode, nearestGateNode, nodes, useDijkstra: false);
        if (tempResult.path.isNotEmpty) {
          if (absoluteBestResult == null || tempResult.totalCost < absoluteBestResult.totalCost) {
            absoluteBestResult = tempResult;
          }
        }
      }
    }

    if (absoluteBestResult == null || absoluteBestResult.path.isEmpty) return;
    final result = absoluteBestResult;

    double totalMeters = 0.0;

    final distance = const Distance();

    for (int i = 0; i < result.path.length - 1; i++) {
      totalMeters += distance.as(
        LengthUnit.Meter,
        result.path[i],
        result.path[i + 1],
      );
    }

    await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .update({
      'safestEvacuationPath': result.path
          .map((p) => {'latitude': p.latitude, 'longitude': p.longitude})
          .toList(),
      'evacuationTriggered': true,
      'estimatedDistance': totalMeters,
    });

    setState(() {
      _evacuationTriggered = true;
      _safestPath = result.path;
      _totalDistance = totalMeters;
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("Live Crowd Heatmap")),

      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .doc(widget.eventId)
            .snapshots(),

        builder: (context, eventSnapshot) {

          if (!eventSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = eventSnapshot.data!.data() as Map<String, dynamic>?;

          if (data == null) {
            return const Center(child: Text("No event data"));
          }

          final venuePolygon = (data['venuePolygon'] as List? ?? [])
              .map((p) => LatLng(p['latitude'], p['longitude']))
              .toList();

          final venueSizeSqM =
              (data['venueSizeSqM'] as num?)?.toDouble() ?? 1.0;

          final gates = (data['gates'] as List? ?? []);

          _evacuationTriggered = data['evacuationTriggered'] ?? false;

          final pathData = data['safestEvacuationPath'] as List? ?? [];

          _safestPath = pathData
              .map((p) => LatLng(p['latitude'], p['longitude']))
              .toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('events')
                .doc(widget.eventId)
                .collection('locations')
                .snapshots(),

            builder: (context, locSnapshot) {

              if (!locSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final positions = locSnapshot.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return LatLng(d['latitude'], d['longitude']);
              }).toList();

              final minLat = venuePolygon.map((p) => p.latitude).reduce(min);
              final maxLat = venuePolygon.map((p) => p.latitude).reduce(max);
              final minLng = venuePolygon.map((p) => p.longitude).reduce(min);
              final maxLng = venuePolygon.map((p) => p.longitude).reduce(max);

              final latStep = (maxLat - minLat) / gridRows;
              final lngStep = (maxLng - minLng) / gridCols;

              final cellArea = venueSizeSqM / (gridRows * gridCols);

              List<List<int>> cellCounts =
                  List.generate(gridRows, (_) => List.filled(gridCols, 0));

              double currentMaxDensity = 0.0;

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

              List<Polygon> heatmapPolygons = [];

              for (int r = 0; r < gridRows; r++) {
                for (int c = 0; c < gridCols; c++) {

                  double density =
                      cellArea > 0 ? (cellCounts[r][c] / cellArea).toDouble() : 0.0;

                  if (density > currentMaxDensity) {
                    currentMaxDensity = density.toDouble();
                  }

                  heatmapPolygons.add(
                    Polygon(
                      points: [
                        LatLng(minLat + r * latStep,
                            minLng + c * lngStep),
                        LatLng(minLat + (r + 1) * latStep,
                            minLng + c * lngStep),
                        LatLng(minLat + (r + 1) * latStep,
                            minLng + (c + 1) * lngStep),
                        LatLng(minLat + r * latStep,
                            minLng + (c + 1) * lngStep),
                      ],
                      color: getDensityColor(density.toDouble()),
                      borderColor: Colors.transparent,
                    ),
                  );
                }
              }

              return Column(
                children: [

                  _buildStatusPanel(currentMaxDensity, criticalThreshold),
                  
                  if (currentMaxDensity >= safeThreshold)
                    Container(
                      width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.warning, color: Colors.white),
                        label: const Text("TRIGGER SAFE EVACUATION"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () {
                           _triggerEvacuation(widget.eventId, cellCounts, venueSizeSqM, venuePolygon);
                        },
                      ),
                    ),
                  ),

                  Expanded(
                    child: FlutterMap(
                      options: MapOptions(
                        center: venuePolygon.first,
                        zoom: 17,
                      ),

                      children: [

                        TileLayer(
                          urlTemplate:
                              "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                          userAgentPackageName: "com.example.newgo",
                        ),

                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: venuePolygon,
                              borderColor: Colors.blue,
                              borderStrokeWidth: 3,
                              color: Colors.blue.withOpacity(0.1),
                            )
                          ],
                        ),

                        PolygonLayer(polygons: heatmapPolygons),

                        if (_safestPath.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _safestPath,
                                strokeWidth: 5,
                                color: Colors.purple,
                                isDotted: true,
                              )
                            ],
                          ),

                        MarkerLayer(
                          markers: gates
                              .map((g) => Marker(
                                    point: LatLng(
                                        g['latitude'], g['longitude']),
                                    child: const Icon(
                                      Icons.door_front_door,
                                      color: Colors.green,
                                      size: 30,
                                    ),
                                  ))
                              .toList(),
                        ),

                        MarkerLayer(
                          markers: positions
                              .map((p) => Marker(
                                    point: p,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFF2C2C2C),
                    alignment: Alignment.center,
                    child: Text(
                      _evacuationTriggered 
                          ? "Evacuation activated. Guiding crowds to safe paths." 
                          : "Crowd density is below emergency threshold.",
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:latlong2/latlong.dart';

// Represents a node (a grid cell center) in the graph.
class GraphNode {
  final String id; // Unique ID for the grid cell (e.g., "row,col")
  final LatLng point; // Center LatLng of the grid cell
  final double densityCost; // Cost based on real-time crowd density

  GraphNode(this.id, this.point, this.densityCost);

  // Override equality for use in search algorithms (like checking if 'openSet' contains a node)
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GraphNode && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// Represents the result of the pathfinding algorithm.
class PathResult {
  final List<LatLng> path; // Sequence of LatLng points to follow
  final double totalCost; // Total calculated cost (distance + crowd penalty)

  PathResult(this.path, this.totalCost);
}

// Represents a single exit gate.
class ExitGate {
  final String name;
  final LatLng point;

  ExitGate(this.name, this.point);
}
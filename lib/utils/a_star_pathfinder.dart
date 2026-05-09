import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'graph_models.dart';

// Helper class to wrap the A* and Dijkstra Pathfinding algorithms
class AStarPathfinder {
  // A large multiplier ensures crowd density is the primary factor in path choice.
  static const double CROWD_MULTIPLIER = 100000.0;

  // Heuristic function: Euclidean Distance
  // If useDijkstra is true, this always returns 0 (making it Dijkstra's algorithm).
  double _heuristic(LatLng start, LatLng goal, bool useDijkstra) {
    if (useDijkstra) return 0.0;
    return sqrt(pow(start.latitude - goal.latitude, 2) +
        pow(start.longitude - goal.longitude, 2));
  }

  // Gets the cost between two adjacent nodes (Grid-to-Grid movement)
  // Total cost = distance + neighbor's crowd penalty
  double _getCost(GraphNode current, GraphNode neighbor) {
    // True distance distance between the two points to ensure actual shortest physical path
    final distance = sqrt(pow(current.point.latitude - neighbor.point.latitude, 2) +
        pow(current.point.longitude - neighbor.point.longitude, 2));

    return distance + (neighbor.densityCost * CROWD_MULTIPLIER);
  }

  // --- Main Pathfinding Function ---
  // If useDijkstra = true, the heuristic is 0, turning A* into Dijkstra's Algorithm.
  PathResult findSafestPath(GraphNode startNode, GraphNode targetNode,
      List<GraphNode> allNodes, {bool useDijkstra = false}) {
      
    Map<String, GraphNode> nodeMap = {for (var node in allNodes) node.id: node};

    // Cost from start to current
    Map<String, double> gScore = {startNode.id: 0};
    
    // To reconstruct the path
    Map<String, String> cameFrom = {};

    // Open Set (Simulated Priority Queue: sorted list by fScore)
    List<GraphNode> openSet = [startNode];
    Map<String, double> fScore = {
      startNode.id: _heuristic(startNode.point, targetNode.point, useDijkstra)
    };

    while (openSet.isNotEmpty) {
      // Find the node in the openSet with the lowest fScore
      openSet.sort((a, b) => fScore[a.id]!.compareTo(fScore[b.id]!));
      GraphNode current = openSet.removeAt(0);

      // --- Goal Test: Check if we reached the target node ---
      if (current.id == targetNode.id) {
        return PathResult(
            _reconstructPath(cameFrom, current.id, nodeMap), gScore[current.id]!);
      }

      // --- Expand Neighbors ---
      List<GraphNode> neighbors = _getNeighbors(current.id, nodeMap);

      for (var neighbor in neighbors) {
        double tentativeGScore =
            gScore[current.id]! + _getCost(current, neighbor);

        if (tentativeGScore < (gScore[neighbor.id] ?? double.infinity)) {
          // This path to neighbor is better. Record it.
          cameFrom[neighbor.id] = current.id;
          gScore[neighbor.id] = tentativeGScore;

          fScore[neighbor.id] = tentativeGScore +
              _heuristic(neighbor.point, targetNode.point, useDijkstra);

          // Add to open set if not present
          if (!openSet.any((n) => n.id == neighbor.id)) {
            openSet.add(neighbor);
          }
        }
      }
    }

    // No path found
    return PathResult([], double.infinity);
  }

  // --- CRUCIAL CUSTOM LOGIC: Find 8 adjacent grid neighbors ---
  List<GraphNode> _getNeighbors(String nodeId, Map<String, GraphNode> nodeMap) {
    // The 'nodeId' is formatted as "row,col" (e.g., "5,3")
    final parts = nodeId.split(',');
    if (parts.length != 2) return [];

    final row = int.tryParse(parts[0]);
    final col = int.tryParse(parts[1]);
    if (row == null || col == null) return [];

    List<GraphNode> neighbors = [];
    const int maxGrid = 10; // Assuming your grid is 10x10

    // Check all 8 directions (including diagonals)
    for (int i = -1; i <= 1; i++) {
      for (int j = -1; j <= 1; j++) {
        if (i == 0 && j == 0) continue; // Skip self

        final newRow = row + i;
        final newCol = col + j;
        final neighborId = '$newRow,$newCol';

        // Ensure the neighbor is within the 10x10 grid bounds
        if (newRow >= 0 &&
            newRow < maxGrid &&
            newCol >= 0 &&
            newCol < maxGrid) {
          final neighborNode = nodeMap[neighborId];
          if (neighborNode != null) {
            neighbors.add(neighborNode);
          }
        }
      }
    }
    return neighbors;
  }

  // Utility to reconstruct the path after the goal is reached
  List<LatLng> _reconstructPath(
      Map<String, String> cameFrom, String currentId, Map<String, GraphNode> nodeMap) {
    List<LatLng> totalPath = [nodeMap[currentId]!.point];
    String? prevId = cameFrom[currentId];
    while (prevId != null) {
      totalPath.insert(0, nodeMap[prevId]!.point);
      prevId = cameFrom[prevId];
    }
    return totalPath;
  }
}
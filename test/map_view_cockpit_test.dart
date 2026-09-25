import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:nav2_mission_planner/widgets/map/occupancy_grid_view.dart';

void main() {
  group('Cockpit View Map Fitting & Matrix Calculations', () {
    test('Calculates optimal scale and translation to center map in viewport', () {
      const viewportSize = Size(1200, 800);
      const mapWidth = 144;
      const mapHeight = 323;

      const padding = 36.0;
      final availableW = max(50.0, viewportSize.width - padding * 2);
      final availableH = max(50.0, viewportSize.height - padding * 2);
      final scaleW = availableW / mapWidth;
      final scaleH = availableH / mapHeight;
      final scale = min(scaleW, scaleH).clamp(0.2, 8.0);

      // Verify that map is scaled to comfortably fit the available height
      expect(scale, closeTo(728 / 323, 0.01));

      final mapScaledW = mapWidth * scale;
      final mapScaledH = mapHeight * scale;
      final tx = (viewportSize.width - mapScaledW) / 2;
      final ty = (viewportSize.height - mapScaledH) / 2;

      // Both margins should be positive and center the map
      expect(tx, greaterThan(0));
      expect(ty, greaterThan(0));
      expect(tx + mapScaledW / 2, closeTo(viewportSize.width / 2, 0.1));
      expect(ty + mapScaledH / 2, closeTo(viewportSize.height / 2, 0.1));

      final matrix = Matrix4.identity()
        ..translateByDouble(tx, ty, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1.0);

      expect(matrix.getMaxScaleOnAxis(), closeTo(scale, 0.001));
    });

    test('NavMsgs OccupancyGrid structure initializes properly for cache', () {
      final grid = nav_msgs.OccupancyGrid(
        info: nav_msgs.MapMetaData(
          width: 144,
          height: 323,
          resolution: 0.05,
          origin: geometry_msgs.Pose(
            position: geometry_msgs.Point(x: -1.834, y: -4.367, z: 0.0),
          ),
        ),
        data: List.filled(144 * 323, 0),
      );

      expect(grid.info.width, equals(144));
      expect(grid.info.height, equals(323));
      expect(grid.info.resolution, closeTo(0.05, 0.001));
      expect(grid.data.length, equals(144 * 323));
    });

    test('worldToPixel and robot centering matrix positions robot at viewport center', () {
      const viewportSize = Size(1200, 800);
      final grid = nav_msgs.OccupancyGrid(
        info: nav_msgs.MapMetaData(
          width: 500,
          height: 400,
          resolution: 0.05,
          origin: geometry_msgs.Pose(
            position: geometry_msgs.Point(x: -10.0, y: -10.0, z: 0.0),
          ),
        ),
        data: List.filled(500 * 400, 0),
      );

      // Robot at world position (2.5, 1.0)
      const rx = 2.5;
      const ry = 1.0;
      final px = worldToPixel(grid, rx, ry);
      expect(px.dx, closeTo(250, 0.01));
      expect(px.dy, closeTo(180, 0.01));

      const currentScale = 1.5;
      final tx = viewportSize.width / 2 - currentScale * px.dx;
      final ty = viewportSize.height / 2 - currentScale * px.dy;

      final matrix = Matrix4.identity()
        ..translateByDouble(tx, ty, 0, 1)
        ..scaleByDouble(currentScale, currentScale, currentScale, 1.0);

      // Verify that transforming the robot's pixel coordinates places it directly at viewport center
      final transformed = MatrixUtils.transformPoint(matrix, px);

      expect(transformed.dx, closeTo(viewportSize.width / 2, 0.001));
      expect(transformed.dy, closeTo(viewportSize.height / 2, 0.001));
    });
  });
}

import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'dart:math' as math;

List<double> quaternionToEuler(geometry_msgs.Quaternion q) {
  final roll =
      math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y));
  final pitch = math.asin(2 * (q.w * q.y - q.z * q.x));
  final yaw =
      math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z));
  return [roll, pitch, yaw];
}

//Euler to quaternion
geometry_msgs.Quaternion eulerToQuaternion(
    double roll, double pitch, double yaw) {
  final qx = math.sin(roll / 2) * math.cos(pitch / 2) * math.cos(yaw / 2) -
      math.cos(roll / 2) * math.sin(pitch / 2) * math.sin(yaw / 2);
  final qy = math.cos(roll / 2) * math.sin(pitch / 2) * math.cos(yaw / 2) +
      math.sin(roll / 2) * math.cos(pitch / 2) * math.sin(yaw / 2);
  final qz = math.cos(roll / 2) * math.cos(pitch / 2) * math.sin(yaw / 2) -
      math.sin(roll / 2) * math.sin(pitch / 2) * math.cos(yaw / 2);
  final qw = math.cos(roll / 2) * math.cos(pitch / 2) * math.cos(yaw / 2) +
      math.sin(roll / 2) * math.sin(pitch / 2) * math.sin(yaw / 2);
  return geometry_msgs.Quaternion(x: qx, y: qy, z: qz, w: qw);
}

({double targetX, double targetY, geometry_msgs.Quaternion orientation})
    transformFromMapFrame(
  double x,
  double y,
  double theta,
  double mapOriginX,
  double mapOriginY,
  double mapResolution,
  int mapHeight,
  int mapWidth,
  double mapOriginTheta,
) {
  // Reverse the Y-axis inversion (image space to world space)
  final worldY = mapHeight - y;

  // Convert map coordinates back to world coordinates
  final targetX = (x * mapResolution) + mapOriginX;
  final targetY = (worldY * mapResolution) + mapOriginY;

  // Reverse the orientation transformation
  final worldYaw = mapOriginTheta - theta;

  return (
    targetX: targetX,
    targetY: targetY,
    orientation: eulerToQuaternion(0, 0, worldYaw)
  );
}

({double x, double y, double theta}) transformToMapFrame(
  double targetX,
  double targetY,
  geometry_msgs.Quaternion orientation,
  double mapOriginX,
  double mapOriginY,
  double mapResolution,
  int mapHeight,
  int mapWidth,
  double mapOriginTheta,
) {
  final originX = mapOriginX;
  final originY = mapOriginY;
  final res = mapResolution;
  final gridHeight = mapHeight;

  // Convert position with proper Y inversion
  final mapX = (targetX - originX) / res;
  final mapY = (targetY - originY) / res;

  // Convert orientation
  final worldYaw = quaternionToEuler(orientation)[2];
  final mapYaw = worldYaw - mapOriginTheta;

  return (
    x: mapX,
    y: gridHeight - mapY, // Proper Y-axis inversion for image space
    theta: -mapYaw
  );
}

// Extract yaw from origin quaternion
double extractYawFromOriginQuaternion(geometry_msgs.Quaternion q) {
  return math.atan2(
      2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z));
}

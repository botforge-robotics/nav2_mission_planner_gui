import {
  sendActionGoal,
  type ActionGoalHandle,
  type Ros2Client,
} from '../ros/Ros2Client';

function yawToQuat(yaw: number) {
  const half = yaw * 0.5;
  return { x: 0, y: 0, z: Math.sin(half), w: Math.cos(half) };
}

export function createGoalService(ros: Ros2Client) {
  let active: ActionGoalHandle | null = null;

  return {
    async navigateToPose(x: number, y: number, theta: number, frameId = 'map') {
      active?.cancel();
      const q = yawToQuat(theta);
      active = sendActionGoal(
        ros,
        '/navigate_to_pose',
        'nav2_msgs/action/NavigateToPose',
        {
          pose: {
            header: { frame_id: frameId, stamp: { sec: 0, nanosec: 0 } },
            pose: {
              position: { x, y, z: 0 },
              orientation: q,
            },
          },
        },
      );
      return active.result;
    },
    cancel() {
      active?.cancel();
      active = null;
    },
  };
}

export function publishInitialPose(
  ros: Ros2Client,
  x: number,
  y: number,
  theta: number,
  frameId = 'map',
) {
  const q = yawToQuat(theta);
  ros.send({ op: 'advertise', topic: '/initialpose', type: 'geometry_msgs/msg/PoseWithCovarianceStamped' });
  ros.send({
    op: 'publish',
    topic: '/initialpose',
    msg: {
      header: { frame_id: frameId, stamp: { sec: 0, nanosec: 0 } },
      pose: {
        pose: {
          position: { x, y, z: 0 },
          orientation: q,
        },
        covariance: Array(36).fill(0),
      },
    },
  });
}

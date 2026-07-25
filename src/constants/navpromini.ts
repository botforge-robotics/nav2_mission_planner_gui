import type { LaunchArg } from './defaults';

/** Built-in preset matching NavProMini robot workspace defaults. */
export const NavProMiniPreset = {
  name: 'NavProMini',
  mappingLaunchFile: 'navpromini_mission_planner/mapping_launch',
  navigationLaunchFile: 'navpromini_mission_planner/navigation_launch',
  mapsPath: 'navpromini_mapping/maps',
  saveMapLaunchFile: 'nav2_mission_planner/save_map',
  cmdVelTopic: '/cmd_vel_teleop',
  twistType: 'geometry_msgs/msg/Twist',
  mappingOdomTopic: '/odom',
  mappingOdomTopicType: 'nav_msgs/msg/Odometry',
  navigationOdomTopic: '/amcl_pose',
  navigationOdomTopicType: 'geometry_msgs/msg/PoseWithCovarianceStamped',
  pathTopic: '/plan',
  lidarTopic: '/scan',
  tfTopic: '/tf',
  mapFrame: 'map',
  odomFrame: 'odom',
  baseLinkFrame: 'base_link',
  cameraImageTopic: '',
  cameraEnabled: false,
  cameraVisible: false,
  joystickVisible: true,
  mappingArgs: [
    { name: 'use_sim_time', value: 'false' },
    { name: 'use_rviz', value: 'false' },
  ] as LaunchArg[],
  navigationArgs: [
    { name: 'use_sim_time', value: 'false' },
    { name: 'use_rviz', value: 'false' },
  ] as LaunchArg[],
} as const;

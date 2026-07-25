import { callService, type Ros2Client } from '../ros/Ros2Client';
import type { LaunchArg } from '../constants/defaults';

const LAUNCH_TYPE =
  'nav2_mission_planner_interfaces/srv/LaunchWithArgs';
const STOP_TYPE = 'nav2_mission_planner_interfaces/srv/StopLaunch';
const MAP_LIST_TYPE = 'nav2_mission_planner_interfaces/srv/GetMapList';
const DELETE_MAP_TYPE = 'nav2_mission_planner_interfaces/srv/DeleteMap';

function formatArgs(args: LaunchArg[]): string {
  return args.map((a) => `${a.name}:=${a.value}`).join(' ');
}

function parseLaunchRef(ref: string): { package: string; launchFile: string } {
  const parts = ref.split('/');
  if (parts.length !== 2) {
    throw new Error('Invalid launch file format (expected package/launch)');
  }
  let launchFile = parts[1];
  if (!launchFile.endsWith('.launch.py')) {
    launchFile = `${launchFile}.launch.py`;
  }
  return { package: parts[0], launchFile };
}

export async function startLaunch(
  ros: Ros2Client,
  launchRef: string,
  args: LaunchArg[],
  timeout: number,
): Promise<{ success: boolean; uniqueId: string; message: string }> {
  const { package: pkg, launchFile } = parseLaunchRef(launchRef);
  const values = await callService(
    ros,
    '/launch_with_args',
    LAUNCH_TYPE,
    {
      package: pkg,
      launch_file: launchFile,
      arguments: formatArgs(args),
    },
    timeout,
  );
  return {
    success: Boolean(values.success),
    uniqueId: String(values.unique_id ?? ''),
    message: String(values.message ?? ''),
  };
}

export async function stopLaunch(
  ros: Ros2Client,
  uniqueId: string,
  timeout: number,
): Promise<void> {
  await callService(
    ros,
    '/stop_launch',
    STOP_TYPE,
    { unique_id: uniqueId },
    timeout,
  );
}

export async function saveMap(
  ros: Ros2Client,
  mapName: string,
  mapsPath: string,
  saveMapArgs: LaunchArg[],
  timeout: number,
): Promise<boolean> {
  const args = [
    ...saveMapArgs,
    { name: 'map_name', value: mapName },
    { name: 'map_path', value: mapsPath },
  ];
  const result = await startLaunch(
    ros,
    'nav2_mission_planner/save_map',
    args,
    timeout,
  );
  return result.success;
}

export async function getMapList(
  ros: Ros2Client,
  mapsPath: string,
  timeout: number,
): Promise<string[]> {
  const values = await callService(
    ros,
    '/get_map_list',
    MAP_LIST_TYPE,
    { path: mapsPath },
    timeout,
  );
  const maps = values.maplist;
  if (Array.isArray(maps)) return maps.map(String);
  return [];
}

export async function deleteMap(
  ros: Ros2Client,
  mapsPath: string,
  mapName: string,
  timeout: number,
): Promise<boolean> {
  const values = await callService(
    ros,
    '/delete_map',
    DELETE_MAP_TYPE,
    { map_path: mapsPath, map_name: mapName },
    timeout,
  );
  return Boolean(values.success ?? true);
}

export async function getStaticMap(
  ros: Ros2Client,
  timeout: number,
): Promise<Record<string, unknown>> {
  return callService(
    ros,
    '/map_server/map',
    'nav_msgs/srv/GetMap',
    {},
    timeout,
  );
}

export async function rosapiTopicsForType(
  ros: Ros2Client,
  type: string,
  timeout: number,
): Promise<string[]> {
  const values = await callService(
    ros,
    '/rosapi/topics_for_type',
    'rosapi_msgs/srv/TopicsForType',
    { type },
    timeout,
  );
  const topics = values.topics;
  return Array.isArray(topics) ? topics.map(String) : [];
}

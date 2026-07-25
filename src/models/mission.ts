export type MissionItemType =
  | 'goto'
  | 'wait'
  | 'publish'
  | 'callService'
  | 'callAction'
  | 'captureImage';

export const MissionItemMeta: Record<
  MissionItemType,
  { displayName: string; color: string }
> = {
  goto: { displayName: 'GOTO', color: '#2196f3' },
  wait: { displayName: 'Wait', color: '#fbc02d' },
  publish: { displayName: 'Publish', color: '#e53935' },
  callService: { displayName: 'Service', color: '#009688' },
  callAction: { displayName: 'Action', color: '#43a047' },
  captureImage: { displayName: 'Capture Image', color: '#f2771a' },
};

export interface Position {
  x: number;
  y: number;
  theta: number;
}

export interface MissionItem {
  id?: string;
  type: MissionItemType;
  name?: string;
  position?: Position;
  waitDuration?: number;
  publishTopic?: string;
  publishMsgType?: string;
  publishMessage?: Record<string, unknown>;
  publishFrequencyType?: 'once' | 'until_next_goal' | 'duration' | 'hz';
  publishDuration?: number;
  publishFrequency?: number;
  serviceName?: string;
  serviceType?: string;
  serviceRequest?: Record<string, unknown>;
  waitForServiceResponse?: boolean;
  actionName?: string;
  actionType?: string;
  actionGoal?: Record<string, unknown>;
  waitForActionResult?: boolean;
}

export interface Mission {
  missionName: string;
  missionDescription: string;
  mapName: string;
  items: MissionItem[];
}

export function missionFromJson(json: Record<string, unknown>): Mission {
  const items = (json.items as Record<string, unknown>[] | undefined) ?? [];
  return {
    missionName: String(json.mission_name ?? json.missionName ?? ''),
    missionDescription: String(
      json.mission_description ?? json.missionDescription ?? '',
    ),
    mapName: String(json.map_name ?? json.mapName ?? ''),
    items: items.map((item) => ({
      id: item.id != null ? String(item.id) : undefined,
      type: String(item.type) as MissionItemType,
      name: item.name != null ? String(item.name) : undefined,
      position: item.position
        ? {
            x: Number((item.position as Position).x),
            y: Number((item.position as Position).y),
            theta: Number((item.position as Position).theta),
          }
        : undefined,
      waitDuration:
        item.waitDuration != null ? Number(item.waitDuration) : undefined,
      publishTopic:
        item.publishTopic != null ? String(item.publishTopic) : undefined,
      publishMsgType:
        item.publishMsgType != null ? String(item.publishMsgType) : undefined,
      publishMessage: item.publishMessage as
        | Record<string, unknown>
        | undefined,
      publishFrequencyType: item.publishFrequencyType as
        | MissionItem['publishFrequencyType']
        | undefined,
      publishDuration:
        item.publishDuration != null
          ? Number(item.publishDuration)
          : undefined,
      publishFrequency:
        item.publishFrequency != null
          ? Number(item.publishFrequency)
          : undefined,
      serviceName:
        item.serviceName != null ? String(item.serviceName) : undefined,
      serviceType:
        item.serviceType != null ? String(item.serviceType) : undefined,
      serviceRequest: item.serviceRequest as
        | Record<string, unknown>
        | undefined,
      waitForServiceResponse:
        item.waitForServiceResponse != null
          ? Boolean(item.waitForServiceResponse)
          : undefined,
      actionName:
        item.actionName != null ? String(item.actionName) : undefined,
      actionType:
        item.actionType != null ? String(item.actionType) : undefined,
      actionGoal: item.actionGoal as Record<string, unknown> | undefined,
      waitForActionResult:
        item.waitForActionResult != null
          ? Boolean(item.waitForActionResult)
          : undefined,
    })),
  };
}

export function missionToJson(mission: Mission): Record<string, unknown> {
  return {
    mission_name: mission.missionName,
    mission_description: mission.missionDescription,
    map_name: mission.mapName,
    items: mission.items,
  };
}

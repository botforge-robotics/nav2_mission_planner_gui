export interface RobotProfile {
  id: string;
  name: string;
  ip: string;
  port: string;
  settingsId: string;
  isConfigured: boolean;
}

export function robotFromJson(json: Record<string, unknown>): RobotProfile {
  return {
    id: String(json.id),
    name: String(json.name),
    ip: String(json.ip),
    port: String(json.port),
    settingsId: String(json.settingsId),
    isConfigured: Boolean(json.isConfigured ?? false),
  };
}

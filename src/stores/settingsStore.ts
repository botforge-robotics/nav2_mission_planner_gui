import { create } from 'zustand';
import { api } from '../api/client';
import { NavProMiniPreset } from '../constants/navpromini';
import type { LaunchArg } from '../constants/defaults';
import type { Bookmark } from '../models/bookmark';
import type { Mission } from '../models/mission';
import { missionFromJson, missionToJson } from '../models/mission';

export interface RobotSettings {
  cmdVelTopic: string;
  linearVelocity: number;
  angularVelocity: number;
  twistType: string;
  mapsPath: string;
  mappingLaunchFile: string;
  mappingOdomTopic: string;
  mappingOdomTopicType: string;
  mappingArgs: LaunchArg[];
  saveMapLaunchFile: string;
  saveMapArgs: LaunchArg[];
  navigationLaunchFile: string;
  navigationOdomTopic: string;
  navigationOdomTopicType: string;
  navigationArgs: LaunchArg[];
  cameraImageTopic: string;
  cameraEnabled: boolean;
  odomTopic: string;
  odomTopicType: string;
  lidarTopic: string;
  communicationTimeout: number;
  cameraVisible: boolean;
  joystickVisible: boolean;
  pathTopic: string;
  tfTopic: string;
  mapFrame: string;
  odomFrame: string;
  baseLinkFrame: string;
  bookmarks: Record<string, Bookmark[]>;
  bookmarksVisible: boolean;
  missions: Record<string, Mission>;
}

function lockedDefaults(): RobotSettings {
  const p = NavProMiniPreset;
  return {
    cmdVelTopic: p.cmdVelTopic,
    linearVelocity: 0.4,
    angularVelocity: 1.0,
    twistType: p.twistType,
    mapsPath: p.mapsPath,
    mappingLaunchFile: p.mappingLaunchFile,
    mappingOdomTopic: p.mappingOdomTopic,
    mappingOdomTopicType: p.mappingOdomTopicType,
    mappingArgs: [...p.mappingArgs],
    saveMapLaunchFile: p.saveMapLaunchFile,
    saveMapArgs: [],
    navigationLaunchFile: p.navigationLaunchFile,
    navigationOdomTopic: p.navigationOdomTopic,
    navigationOdomTopicType: p.navigationOdomTopicType,
    navigationArgs: [...p.navigationArgs],
    cameraImageTopic: '',
    cameraEnabled: false,
    odomTopic: '/odom',
    odomTopicType: 'nav_msgs/msg/Odometry',
    lidarTopic: p.lidarTopic,
    communicationTimeout: 120,
    cameraVisible: false,
    joystickVisible: true,
    pathTopic: p.pathTopic,
    tfTopic: p.tfTopic,
    mapFrame: p.mapFrame,
    odomFrame: p.odomFrame,
    baseLinkFrame: p.baseLinkFrame,
    bookmarks: {},
    bookmarksVisible: true,
    missions: {},
  };
}

function normalize(raw: Record<string, unknown>): RobotSettings {
  const base = lockedDefaults();
  const bookmarks = (raw.bookmarks as Record<string, Bookmark[]>) || {};
  const missionsRaw = (raw.missions as Record<string, Record<string, unknown>>) || {};
  const missions: Record<string, Mission> = {};
  for (const [k, v] of Object.entries(missionsRaw)) {
    missions[k] = missionFromJson(v);
  }
  return {
    ...base,
    linearVelocity: Number(raw.linearVelocity ?? base.linearVelocity),
    angularVelocity: Number(raw.angularVelocity ?? base.angularVelocity),
    communicationTimeout: Number(
      raw.communicationTimeout ?? base.communicationTimeout,
    ),
    joystickVisible: Boolean(raw.joystickVisible ?? base.joystickVisible),
    bookmarksVisible: Boolean(raw.bookmarksVisible ?? base.bookmarksVisible),
    bookmarks,
    missions,
  };
}

interface SettingsState {
  settings: RobotSettings;
  loaded: boolean;
  loadFromApi: () => Promise<void>;
  update: (patch: Partial<RobotSettings>) => Promise<void>;
  applyNavProMiniPreset: () => Promise<void>;
  saveMission: (mission: Mission) => Promise<void>;
  deleteMission: (name: string) => Promise<void>;
  setBookmarksForMap: (mapName: string, bookmarks: Bookmark[]) => Promise<void>;
}

export const useSettingsStore = create<SettingsState>((set, get) => ({
  settings: lockedDefaults(),
  loaded: false,

  async loadFromApi() {
    try {
      const raw = await api.getSettings();
      set({ settings: normalize(raw), loaded: true });
    } catch {
      set({ settings: lockedDefaults(), loaded: true });
    }
  },

  async update(patch) {
    const next = normalize({ ...get().settings, ...patch } as unknown as Record<string, unknown>);
    // serialize missions for API
    const payload = {
      ...next,
      missions: Object.fromEntries(
        Object.entries(next.missions).map(([k, m]) => [k, missionToJson(m)]),
      ),
    };
    set({ settings: next });
    try {
      const saved = await api.putSettings(payload as unknown as Record<string, unknown>);
      set({ settings: normalize(saved) });
    } catch {
      /* keep local */
    }
  },

  async applyNavProMiniPreset() {
    await get().update(lockedDefaults());
  },

  async saveMission(mission) {
    const missions = { ...get().settings.missions, [mission.missionName]: mission };
    await get().update({ missions });
  },

  async deleteMission(name) {
    const missions = { ...get().settings.missions };
    delete missions[name];
    await get().update({ missions });
  },

  async setBookmarksForMap(mapName, bookmarks) {
    const all = { ...get().settings.bookmarks, [mapName]: bookmarks };
    await get().update({ bookmarks: all });
  },
}));

import { create } from 'zustand';
import { api, type ClaimedRobot, type NearbyRobot } from '../api/client';
import { Ros2Client } from '../ros/Ros2Client';
import type { RosStatus } from '../ros/Ros2Client';
import { useSettingsStore } from './settingsStore';

interface RobotState {
  claimed: ClaimedRobot | null;
  nearby: NearbyRobot[];
  online: boolean;
  scanning: boolean;
  isConnected: boolean;
  status: RosStatus;
  ros: Ros2Client | null;
  error: string | null;
  bootstrapped: boolean;
  bootstrap: () => Promise<void>;
  scanNearby: () => Promise<void>;
  claimRobot: (robot: {
    name?: string;
    ip: string;
    port?: string;
    id?: string;
  }) => Promise<void>;
  unclaim: () => Promise<void>;
  connectClaimed: () => Promise<boolean>;
  disconnect: () => void;
  pollHeartbeat: () => Promise<void>;
}

export const useRobotStore = create<RobotState>((set, get) => ({
  claimed: null,
  nearby: [],
  online: false,
  scanning: false,
  isConnected: false,
  status: 'none',
  ros: null,
  error: null,
  bootstrapped: false,

  async bootstrap() {
    try {
      await useSettingsStore.getState().loadFromApi();
      const claimed = await api.getClaim();
      set({ claimed, bootstrapped: true });
      if (claimed) {
        await get().connectClaimed();
        await get().pollHeartbeat();
      } else {
        await get().scanNearby();
      }
    } catch (e) {
      set({
        bootstrapped: true,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  },

  async scanNearby() {
    set({ scanning: true, error: null });
    try {
      const { robots } = await api.nearby(true);
      set({ nearby: robots, scanning: false });
    } catch (e) {
      set({
        scanning: false,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  },

  async claimRobot(robot) {
    const { robot: claimed, online } = await api.claim(robot);
    set({ claimed, online });
    await useSettingsStore.getState().loadFromApi();
    await get().connectClaimed();
  },

  async unclaim() {
    get().disconnect();
    await api.unclaim();
    set({ claimed: null, online: false });
    await get().scanNearby();
  },

  async connectClaimed() {
    const claimed = get().claimed;
    if (!claimed) return false;
    set({ error: null, status: 'connecting' });
    get().ros?.close();
    const ros = new Ros2Client(`ws://${claimed.ip}:${claimed.port}`);
    return new Promise((resolve) => {
      const unsub = ros.onStatus((status) => {
        set({ status, isConnected: status === 'connected', ros });
        if (status === 'connected') {
          unsub();
          resolve(true);
        } else if (status === 'errored' || status === 'closed') {
          // keep listening briefly; resolve false after first fail
        }
      });
      ros.connect();
      window.setTimeout(() => {
        if (get().status !== 'connected') {
          unsub();
          set({ error: `Cannot reach rosbridge at ${claimed.ip}:${claimed.port}` });
          resolve(false);
        }
      }, 4000);
    });
  },

  disconnect() {
    get().ros?.close();
    set({ ros: null, isConnected: false, status: 'closed' });
  },

  async pollHeartbeat() {
    try {
      const hb = await api.heartbeat();
      set({
        claimed: hb.robot ?? get().claimed,
        online: hb.online,
      });
      if (hb.online && !get().isConnected) {
        await get().connectClaimed();
      }
      if (!hb.online && get().isConnected) {
        get().disconnect();
      }
    } catch {
      set({ online: false });
    }
  },
}));

/** @deprecated use useRobotStore */
export const useConnectionStore = useRobotStore;

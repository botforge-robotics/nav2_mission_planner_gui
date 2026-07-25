import { create } from 'zustand';

export type SessionType = 'none' | 'mapping' | 'navigation';
export type AppMode = 'teleop' | 'mapping' | 'navigation' | 'settings';

interface AppUiState {
  mode: AppMode;
  previousMode: AppMode;
  activeSession: SessionType;
  activeLaunches: Record<string, string>;
  selectedMap: string | null;
  toast: string | null;
  setMode: (mode: AppMode) => void;
  setSession: (session: SessionType) => void;
  trackLaunch: (id: string, description: string) => void;
  clearLaunch: (id: string) => void;
  clearAllLaunches: () => void;
  setSelectedMap: (map: string | null) => void;
  showToast: (msg: string) => void;
  clearToast: () => void;
}

export const useAppStore = create<AppUiState>((set, get) => ({
  mode: 'teleop',
  previousMode: 'teleop',
  activeSession: 'none',
  activeLaunches: {},
  selectedMap: null,
  toast: null,
  setMode(mode) {
    const prev = get().mode;
    if (mode === 'settings') {
      set({ previousMode: prev === 'settings' ? get().previousMode : prev, mode });
    } else {
      set({ mode, previousMode: mode });
    }
  },
  setSession(session) {
    set({ activeSession: session });
  },
  trackLaunch(id, description) {
    set({ activeLaunches: { ...get().activeLaunches, [id]: description } });
  },
  clearLaunch(id) {
    const next = { ...get().activeLaunches };
    delete next[id];
    set({ activeLaunches: next, activeSession: 'none' });
  },
  clearAllLaunches() {
    set({ activeLaunches: {}, activeSession: 'none' });
  },
  setSelectedMap(map) {
    set({ selectedMap: map });
  },
  showToast(msg) {
    set({ toast: msg });
    window.setTimeout(() => {
      if (get().toast === msg) set({ toast: null });
    }, 4000);
  },
  clearToast() {
    set({ toast: null });
  },
}));

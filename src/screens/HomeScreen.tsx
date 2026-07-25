import { useEffect } from 'react';
import { TopStatusBar } from '../components/TopStatusBar';
import { ClaimPanel, useHeartbeatLoop } from '../components/ClaimPanel';
import { TeleopScreen } from './TeleopScreen';
import { MappingScreen } from './MappingScreen';
import { NavigationScreen } from './NavigationScreen';
import { SettingsScreen } from './SettingsScreen';
import { useAppStore } from '../stores/appStore';
import { useRobotStore } from '../stores/connectionStore';

export function HomeScreen() {
  const mode = useAppStore((s) => s.mode);
  const toast = useAppStore((s) => s.toast);
  const bootstrapped = useRobotStore((s) => s.bootstrapped);
  const claimed = useRobotStore((s) => s.claimed);
  const isConnected = useRobotStore((s) => s.isConnected);
  const bootstrap = useRobotStore((s) => s.bootstrap);

  useEffect(() => {
    void bootstrap();
  }, [bootstrap]);

  useHeartbeatLoop(Boolean(claimed));

  if (!bootstrapped) {
    return (
      <div className="home-screen boot">
        <p>Loading…</p>
      </div>
    );
  }

  if (!claimed || !isConnected) {
    return (
      <div className="home-screen">
        <TopStatusBar />
        <main className="home-main claim-main">
          <ClaimPanel />
        </main>
        {toast && <div className="toast">{toast}</div>}
      </div>
    );
  }

  return (
    <div className="home-screen">
      <TopStatusBar />
      <main className="home-main">
        <div className={mode === 'teleop' ? 'pane active' : 'pane'}>
          <TeleopScreen />
        </div>
        <div className={mode === 'mapping' ? 'pane active' : 'pane'}>
          <MappingScreen />
        </div>
        <div className={mode === 'navigation' ? 'pane active' : 'pane'}>
          <NavigationScreen />
        </div>
        <div className={mode === 'settings' ? 'pane active' : 'pane'}>
          <SettingsScreen />
        </div>
      </main>
      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}

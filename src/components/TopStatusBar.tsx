import { branding, theme } from '../constants/theme';
import { useAppStore, type AppMode } from '../stores/appStore';
import { useRobotStore } from '../stores/connectionStore';

const modes: { id: AppMode; label: string }[] = [
  { id: 'teleop', label: 'Teleop' },
  { id: 'mapping', label: 'Mapping' },
  { id: 'navigation', label: 'Navigation' },
  { id: 'settings', label: 'Settings' },
];

export function TopStatusBar() {
  const mode = useAppStore((s) => s.mode);
  const setMode = useAppStore((s) => s.setMode);
  const session = useAppStore((s) => s.activeSession);
  const claimed = useRobotStore((s) => s.claimed);
  const online = useRobotStore((s) => s.online);
  const isConnected = useRobotStore((s) => s.isConnected);

  return (
    <header className="status-bar">
      <div className="status-brand">
        <img src="/nmpLogo.png" alt="" className="status-logo" />
        <span>{branding.title}</span>
      </div>
      <nav className="mode-switcher">
        {modes.map((m) => (
          <button
            key={m.id}
            className={mode === m.id ? 'active' : ''}
            style={mode === m.id ? { borderBottomColor: theme.brand } : undefined}
            onClick={() => setMode(m.id)}
            disabled={!isConnected}
          >
            {m.label}
          </button>
        ))}
      </nav>
      <div className="status-meta">
        {session !== 'none' && <span className="badge session">{session}</span>}
        <span className={`badge ${online ? 'ok' : 'err'}`}>
          {online ? 'hb' : 'no hb'}
        </span>
        <span className={`badge ${isConnected ? 'ok' : 'err'}`}>
          {isConnected ? 'connected' : 'offline'}
        </span>
        <span className="robot-name">{claimed?.name ?? 'unclaimed'}</span>
      </div>
    </header>
  );
}

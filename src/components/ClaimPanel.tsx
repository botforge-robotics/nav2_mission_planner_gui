import { useEffect, useState } from 'react';
import { useRobotStore } from '../stores/connectionStore';

export function ClaimPanel() {
  const {
    claimed,
    nearby,
    scanning,
    online,
    isConnected,
    error,
    scanNearby,
    claimRobot,
    unclaim,
    connectClaimed,
  } = useRobotStore();
  const [manualIp, setManualIp] = useState('');
  const [manualName, setManualName] = useState('NavProMini');

  if (claimed) {
    return (
      <div className="claim-panel claimed">
        <div>
          <strong>{claimed.name}</strong>
          <span className="muted">
            {' '}
            {claimed.ip}:{claimed.port}
          </span>
          <span className={`badge ${online ? 'ok' : 'err'}`}>
            {online ? 'heartbeat ok' : 'offline'}
          </span>
          <span className={`badge ${isConnected ? 'ok' : 'err'}`}>
            {isConnected ? 'rosbridge' : 'no ws'}
          </span>
        </div>
        <div className="row">
          <button className="ghost" onClick={() => void connectClaimed()}>
            Reconnect
          </button>
          <button className="danger ghost" onClick={() => void unclaim()}>
            Release
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="claim-panel">
      <h2>Claim your NavProMini</h2>
      <p className="muted">
        This app is fixed to NavProMini defaults (topics, launches, maps). Find a
        robot on the LAN with rosbridge :9090 and claim it.
      </p>
      {error && <p className="error">{error}</p>}
      <div className="row">
        <button disabled={scanning} onClick={() => void scanNearby()}>
          {scanning ? 'Scanning…' : 'Scan nearby'}
        </button>
      </div>
      <ul className="nearby-list">
        {nearby.map((r) => (
          <li key={r.id}>
            <div>
              <strong>{r.name}</strong>
              <span className="muted">
                {' '}
                {r.ip}:{r.port}
              </span>
            </div>
            <button
              onClick={() =>
                void claimRobot({ name: r.name, ip: r.ip, port: r.port, id: r.id })
              }
            >
              Claim
            </button>
          </li>
        ))}
        {!scanning && nearby.length === 0 && (
          <li className="muted">No robots found yet — try scan or enter IP.</li>
        )}
      </ul>
      <div className="manual-claim">
        <label>
          Name
          <input value={manualName} onChange={(e) => setManualName(e.target.value)} />
        </label>
        <label>
          Robot IP
          <input
            placeholder="192.168.1.50"
            value={manualIp}
            onChange={(e) => setManualIp(e.target.value)}
          />
        </label>
        <button
          disabled={!manualIp}
          onClick={() =>
            void claimRobot({ name: manualName, ip: manualIp, port: '9090' })
          }
        >
          Claim IP
        </button>
      </div>
    </div>
  );
}

export function useHeartbeatLoop(enabled: boolean) {
  const pollHeartbeat = useRobotStore((s) => s.pollHeartbeat);
  useEffect(() => {
    if (!enabled) return;
    const id = window.setInterval(() => void pollHeartbeat(), 3000);
    void pollHeartbeat();
    return () => window.clearInterval(id);
  }, [enabled, pollHeartbeat]);
}

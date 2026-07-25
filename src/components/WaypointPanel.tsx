import { useMemo, useState } from 'react';
import { v4 as uuidv4 } from 'uuid';
import type { Mission, MissionItem, MissionItemType } from '../models/mission';
import { MissionItemMeta } from '../models/mission';
import { useSettingsStore } from '../stores/settingsStore';
import { missionExecutor } from '../services/missionExecution';
import { useConnectionStore } from '../stores/connectionStore';
import { useAppStore } from '../stores/appStore';

interface Props {
  mapName: string;
  draftWaypoints: MissionItem[];
  onClearDraft: () => void;
}

export function WaypointPanel({ mapName, draftWaypoints, onClearDraft }: Props) {
  const settings = useSettingsStore((s) => s.settings);
  const saveMission = useSettingsStore((s) => s.saveMission);
  const deleteMission = useSettingsStore((s) => s.deleteMission);
  const ros = useConnectionStore((s) => s.ros);
  const showToast = useAppStore((s) => s.showToast);

  const missions = useMemo(
    () =>
      Object.values(settings.missions).filter((m) => m.mapName === mapName),
    [settings.missions, mapName],
  );

  const [name, setName] = useState('New Mission');
  const [desc, setDesc] = useState('');
  const [selected, setSelected] = useState<Mission | null>(null);
  const [running, setRunning] = useState(false);

  const buildFromDraft = (): Mission => ({
    missionName: name,
    missionDescription: desc,
    mapName,
    items: draftWaypoints.map((w, i) => ({
      ...w,
      id: w.id ?? uuidv4(),
      name: w.name ?? `WP ${i + 1}`,
    })),
  });

  const addWait = () => {
    if (!selected) return;
    const item: MissionItem = {
      id: uuidv4(),
      type: 'wait',
      name: 'Wait',
      waitDuration: 2,
    };
    const next = { ...selected, items: [...selected.items, item] };
    setSelected(next);
    saveMission(next);
  };

  return (
    <aside className="waypoint-panel">
      <h3>Missions — {mapName || 'no map'}</h3>
      <div className="panel-section">
        <label>
          Name
          <input value={name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          Description
          <input value={desc} onChange={(e) => setDesc(e.target.value)} />
        </label>
        <p className="muted">{draftWaypoints.length} draft waypoints</p>
        <div className="row">
          <button
            onClick={() => {
              const m = buildFromDraft();
              saveMission(m);
              setSelected(m);
              onClearDraft();
              showToast(`Saved mission ${m.missionName}`);
            }}
            disabled={!mapName || draftWaypoints.length === 0}
          >
            Save mission
          </button>
          <button className="ghost" onClick={onClearDraft}>
            Clear draft
          </button>
        </div>
      </div>

      <div className="panel-section">
        <h4>Saved</h4>
        <ul className="mission-list">
          {missions.map((m) => (
            <li key={m.missionName}>
              <button
                className={selected?.missionName === m.missionName ? 'active' : ''}
                onClick={() => setSelected(m)}
              >
                {m.missionName} ({m.items.length})
              </button>
              <button
                className="danger ghost"
                onClick={() => deleteMission(m.missionName)}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      </div>

      {selected && (
        <div className="panel-section">
          <h4>{selected.missionName}</h4>
          <ol className="item-list">
            {selected.items.map((item, idx) => (
              <li key={item.id ?? idx}>
                <span
                  className="chip"
                  style={{ background: MissionItemMeta[item.type as MissionItemType].color }}
                >
                  {MissionItemMeta[item.type as MissionItemType].displayName}
                </span>
                {item.name ?? item.type}
              </li>
            ))}
          </ol>
          <div className="row">
            <button onClick={addWait}>+ Wait</button>
            <button
              disabled={!ros || running}
              onClick={async () => {
                if (!ros) return;
                setRunning(true);
                await missionExecutor.start(
                  ros,
                  selected,
                  settings.cameraEnabled ? settings.cameraImageTopic : undefined,
                );
                setRunning(false);
                showToast('Mission finished');
              }}
            >
              {running ? 'Running…' : 'Execute'}
            </button>
            <button
              className="ghost"
              onClick={() => missionExecutor.cancel()}
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </aside>
  );
}

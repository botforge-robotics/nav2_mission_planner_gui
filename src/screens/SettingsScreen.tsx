import { branding } from '../constants/theme';
import { useSettingsStore } from '../stores/settingsStore';
import { useState } from 'react';
import { ClaimPanel } from '../components/ClaimPanel';

const categories = ['Robot', 'Teleop UI', 'About'] as const;

export function SettingsScreen() {
  const [cat, setCat] = useState<(typeof categories)[number]>('Robot');
  const settings = useSettingsStore((s) => s.settings);
  const update = useSettingsStore((s) => s.update);

  return (
    <div className="settings-screen">
      <aside className="settings-nav">
        {categories.map((c) => (
          <button
            key={c}
            className={cat === c ? 'active' : ''}
            onClick={() => setCat(c)}
          >
            {c}
          </button>
        ))}
      </aside>
      <div className="settings-content">
        {cat === 'Robot' && (
          <>
            <p className="muted">
              Launch files, topics, and frames are locked to NavProMini defaults
              and stored in the app database.
            </p>
            <ClaimPanel />
            <div className="locked-defaults">
              <h4>Locked defaults</h4>
              <ul>
                <li>cmd_vel: {settings.cmdVelTopic}</li>
                <li>twist: {settings.twistType}</li>
                <li>mapping: {settings.mappingLaunchFile}</li>
                <li>navigation: {settings.navigationLaunchFile}</li>
                <li>maps: {settings.mapsPath}</li>
                <li>scan: {settings.lidarTopic}</li>
                <li>path: {settings.pathTopic}</li>
              </ul>
            </div>
          </>
        )}

        {cat === 'Teleop UI' && (
          <>
            <label>
              Max linear / angular
              <div className="row">
                <input
                  type="number"
                  step="0.05"
                  value={settings.linearVelocity}
                  onChange={(e) =>
                    void update({ linearVelocity: Number(e.target.value) })
                  }
                />
                <input
                  type="number"
                  step="0.05"
                  value={settings.angularVelocity}
                  onChange={(e) =>
                    void update({ angularVelocity: Number(e.target.value) })
                  }
                />
              </div>
            </label>
            <label className="check">
              <input
                type="checkbox"
                checked={settings.joystickVisible}
                onChange={(e) =>
                  void update({ joystickVisible: e.target.checked })
                }
              />
              Joystick visible
            </label>
            <label className="check">
              <input
                type="checkbox"
                checked={settings.bookmarksVisible}
                onChange={(e) =>
                  void update({ bookmarksVisible: e.target.checked })
                }
              />
              Bookmarks visible
            </label>
          </>
        )}

        {cat === 'About' && (
          <div className="about">
            <h2>{branding.title}</h2>
            <p>{branding.tagline}</p>
            <p>Single-robot NavProMini web console with SQLite-backed claim & settings.</p>
          </div>
        )}
      </div>
    </div>
  );
}

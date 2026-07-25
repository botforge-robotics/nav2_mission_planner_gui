import { useEffect, useRef, useState } from 'react';
import { OccupancyGridViewer } from '../components/OccupancyGridViewer';
import { Joystick } from '../components/Joystick';
import { createPublisher, createSubscriber } from '../ros/Ros2Client';
import { useConnectionStore } from '../stores/connectionStore';
import { useSettingsStore } from '../stores/settingsStore';
import { useAppStore } from '../stores/appStore';
import {
  saveMap,
  startLaunch,
  stopLaunch,
} from '../services/launchService';

export function MappingScreen() {
  const ros = useConnectionStore((s) => s.ros);
  const settings = useSettingsStore((s) => s.settings);
  const {
    activeSession,
    activeLaunches,
    setSession,
    trackLaunch,
    clearLaunch,
    showToast,
  } = useAppStore();
  const [mapName, setMapName] = useState('navpromini_map');
  const [robotPose, setRobotPose] = useState<{ x: number; y: number; theta: number } | null>(null);
  const pubRef = useRef<ReturnType<typeof createPublisher> | null>(null);

  useEffect(() => {
    if (!ros) return;
    pubRef.current = createPublisher(ros, settings.cmdVelTopic, settings.twistType);
    return () => pubRef.current?.shutdown();
  }, [ros, settings.cmdVelTopic, settings.twistType]);

  useEffect(() => {
    if (!ros) return;
    const topic = settings.mappingOdomTopic;
    const type = settings.mappingOdomTopicType;
    const sub = createSubscriber(ros, topic, type, (msg) => {
      const pose =
        (msg.pose as { pose?: { position: { x: number; y: number }; orientation: { z: number; w: number } } })
          ?.pose ??
        (msg as { pose: { position: { x: number; y: number }; orientation: { z: number; w: number } } }).pose;
      if (!pose?.position) return;
      const q = pose.orientation;
      const theta = Math.atan2(2 * (q.w * q.z), 1 - 2 * (q.z * q.z));
      setRobotPose({ x: pose.position.x, y: pose.position.y, theta });
    });
    return () => sub.shutdown();
  }, [ros, settings.mappingOdomTopic, settings.mappingOdomTopicType]);

  const publishTwist = (linear: number, angular: number) => {
    if (!pubRef.current) return;
    const twist = {
      linear: { x: linear, y: 0, z: 0 },
      angular: { x: 0, y: 0, z: angular },
    };
    if (settings.twistType.includes('TwistStamped')) {
      pubRef.current.publish({
        header: { frame_id: settings.baseLinkFrame, stamp: { sec: 0, nanosec: 0 } },
        twist,
      });
    } else {
      pubRef.current.publish(twist);
    }
  };

  const mappingId = Object.keys(activeLaunches).find((id) =>
    activeLaunches[id].includes(settings.mappingLaunchFile.split('/')[0]),
  );

  return (
    <div className="mapping-screen">
      <div className="side-tools">
        <button
          disabled={!ros || activeSession === 'mapping'}
          onClick={async () => {
            if (!ros) return;
            try {
              const res = await startLaunch(
                ros,
                settings.mappingLaunchFile,
                settings.mappingArgs,
                settings.communicationTimeout,
              );
              if (res.success) {
                trackLaunch(res.uniqueId, settings.mappingLaunchFile);
                setSession('mapping');
                showToast('Mapping started');
              } else showToast(res.message || 'Failed to start mapping');
            } catch (e) {
              showToast(String(e));
            }
          }}
        >
          Start mapping
        </button>
        <button
          disabled={!ros || !mappingId}
          onClick={async () => {
            if (!ros || !mappingId) return;
            await stopLaunch(ros, mappingId, settings.communicationTimeout);
            clearLaunch(mappingId);
            showToast('Mapping stopped');
          }}
        >
          Stop
        </button>
        <label>
          Map name
          <input value={mapName} onChange={(e) => setMapName(e.target.value)} />
        </label>
        <button
          disabled={!ros}
          onClick={async () => {
            if (!ros) return;
            const ok = await saveMap(
              ros,
              mapName,
              settings.mapsPath,
              settings.saveMapArgs,
              settings.communicationTimeout,
            );
            showToast(ok ? `Saved ${mapName}` : 'Save failed');
          }}
        >
          Save map
        </button>
      </div>
      <OccupancyGridViewer ros={ros} robotPose={robotPose} />
      <Joystick
        visible={settings.joystickVisible}
        maxLinear={settings.linearVelocity}
        maxAngular={settings.angularVelocity}
        onMove={publishTwist}
        onStop={() => publishTwist(0, 0)}
      />
    </div>
  );
}

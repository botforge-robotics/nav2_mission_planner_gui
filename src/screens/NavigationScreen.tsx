import { useEffect, useMemo, useRef, useState } from 'react';
import { v4 as uuidv4 } from 'uuid';
import { OccupancyGridViewer } from '../components/OccupancyGridViewer';
import { Joystick } from '../components/Joystick';
import { WaypointPanel } from '../components/WaypointPanel';
import { ImageViewer } from '../components/ImageViewer';
import { createPublisher, createSubscriber } from '../ros/Ros2Client';
import { useConnectionStore } from '../stores/connectionStore';
import { useSettingsStore } from '../stores/settingsStore';
import { useAppStore } from '../stores/appStore';
import {
  deleteMap,
  getMapList,
  startLaunch,
  stopLaunch,
} from '../services/launchService';
import { createGoalService, publishInitialPose } from '../services/goalService';
import type { MissionItem } from '../models/mission';
import type { Bookmark } from '../models/bookmark';

type Tool = 'none' | 'localize' | 'goal' | 'bookmark' | 'waypoint';

export function NavigationScreen() {
  const ros = useConnectionStore((s) => s.ros);
  const settings = useSettingsStore((s) => s.settings);
  const setBookmarksForMap = useSettingsStore((s) => s.setBookmarksForMap);
  const {
    selectedMap,
    setSelectedMap,
    activeSession,
    activeLaunches,
    setSession,
    trackLaunch,
    clearLaunch,
    showToast,
  } = useAppStore();

  const [maps, setMaps] = useState<string[]>([]);
  const [tool, setTool] = useState<Tool>('none');
  const [robotPose, setRobotPose] = useState<{ x: number; y: number; theta: number } | null>(null);
  const [goalPose, setGoalPose] = useState<{ x: number; y: number; theta: number } | null>(null);
  const [path, setPath] = useState<Array<{ x: number; y: number }>>([]);
  const [draftWaypoints, setDraftWaypoints] = useState<MissionItem[]>([]);
  const [goalYaw, setGoalYaw] = useState(0);
  const [showCamera, setShowCamera] = useState(false);
  const pubRef = useRef<ReturnType<typeof createPublisher> | null>(null);
  const goalRef = useRef<ReturnType<typeof createGoalService> | null>(null);

  const bookmarks = useMemo(
    () => (selectedMap ? settings.bookmarks[selectedMap] ?? [] : []),
    [settings.bookmarks, selectedMap],
  );

  useEffect(() => {
    if (!ros) return;
    pubRef.current = createPublisher(ros, settings.cmdVelTopic, settings.twistType);
    goalRef.current = createGoalService(ros);
    return () => {
      pubRef.current?.shutdown();
      goalRef.current?.cancel();
    };
  }, [ros, settings.cmdVelTopic, settings.twistType]);

  useEffect(() => {
    if (!ros) return;
    void getMapList(ros, settings.mapsPath, settings.communicationTimeout)
      .then(setMaps)
      .catch((e) => showToast(String(e)));
  }, [ros, settings.mapsPath, settings.communicationTimeout, showToast]);

  useEffect(() => {
    if (!ros) return;
    const sub = createSubscriber(
      ros,
      settings.navigationOdomTopic,
      settings.navigationOdomTopicType,
      (msg) => {
        const poseMsg =
          (msg.pose as { pose?: { position: { x: number; y: number }; orientation: { z: number; w: number } } })
            ?.pose ??
          (msg as {
            pose: {
              position: { x: number; y: number };
              orientation: { z: number; w: number };
            };
          }).pose;
        if (!poseMsg?.position) return;
        const q = poseMsg.orientation;
        const theta = Math.atan2(2 * (q.w * q.z), 1 - 2 * (q.z * q.z));
        setRobotPose({ x: poseMsg.position.x, y: poseMsg.position.y, theta });
      },
    );
    return () => sub.shutdown();
  }, [ros, settings.navigationOdomTopic, settings.navigationOdomTopicType]);

  useEffect(() => {
    if (!ros) return;
    const sub = createSubscriber(ros, settings.pathTopic, 'nav_msgs/msg/Path', (msg) => {
      const poses = (msg.poses as Array<{ pose: { position: { x: number; y: number } } }>) ?? [];
      setPath(poses.map((p) => ({ x: p.pose.position.x, y: p.pose.position.y })));
    });
    return () => sub.shutdown();
  }, [ros, settings.pathTopic]);

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

  const navId = Object.keys(activeLaunches)[0];

  return (
    <div className="navigation-screen">
      <div className="nav-toolbar">
        <select
          value={selectedMap ?? ''}
          onChange={(e) => setSelectedMap(e.target.value || null)}
        >
          <option value="">Select map</option>
          {maps.map((m) => (
            <option key={m} value={m.replace(/\.yaml$/, '')}>
              {m.replace(/\.yaml$/, '')}
            </option>
          ))}
        </select>
        <button
          disabled={!ros || !selectedMap || activeSession === 'navigation'}
          onClick={async () => {
            if (!ros || !selectedMap) return;
            try {
              const res = await startLaunch(
                ros,
                settings.navigationLaunchFile,
                [
                  ...settings.navigationArgs,
                  { name: 'map', value: `${selectedMap}.yaml` },
                ],
                settings.communicationTimeout,
              );
              if (res.success) {
                trackLaunch(res.uniqueId, settings.navigationLaunchFile);
                setSession('navigation');
                showToast('Navigation started');
              } else showToast(res.message || 'Failed');
            } catch (e) {
              showToast(String(e));
            }
          }}
        >
          Start nav
        </button>
        <button
          disabled={!ros || !navId}
          onClick={async () => {
            if (!ros || !navId) return;
            await stopLaunch(ros, navId, settings.communicationTimeout);
            clearLaunch(navId);
          }}
        >
          Stop
        </button>
        <button
          disabled={!ros || !selectedMap}
          onClick={async () => {
            if (!ros || !selectedMap) return;
            await deleteMap(
              ros,
              settings.mapsPath,
              selectedMap,
              settings.communicationTimeout,
            );
            setMaps((m) => m.filter((x) => !x.includes(selectedMap)));
            setSelectedMap(null);
          }}
        >
          Delete map
        </button>
        {(['localize', 'goal', 'bookmark', 'waypoint'] as Tool[]).map((t) => (
          <button
            key={t}
            className={tool === t ? 'active' : ''}
            onClick={() => setTool(tool === t ? 'none' : t)}
          >
            {t}
          </button>
        ))}
        <button onClick={() => setShowCamera((v) => !v)}>Camera</button>
        {tool === 'goal' && (
          <label className="yaw">
            Yaw
            <input
              type="range"
              min={-Math.PI}
              max={Math.PI}
              step={0.05}
              value={goalYaw}
              onChange={(e) => setGoalYaw(Number(e.target.value))}
            />
          </label>
        )}
      </div>

      <div className="nav-body">
        <OccupancyGridViewer
          ros={ros}
          robotPose={robotPose}
          goalPose={goalPose}
          path={path}
          bookmarks={settings.bookmarksVisible ? bookmarks : []}
          missionItems={draftWaypoints}
          tool={tool}
          onMapClick={(pose) => {
            const withYaw = { ...pose, theta: goalYaw };
            if (tool === 'localize' && ros) {
              publishInitialPose(ros, withYaw.x, withYaw.y, withYaw.theta, settings.mapFrame);
              showToast('Initial pose published');
            } else if (tool === 'goal' && ros) {
              setGoalPose(withYaw);
              void goalRef.current
                ?.navigateToPose(withYaw.x, withYaw.y, withYaw.theta, settings.mapFrame)
                .catch((e) => showToast(String(e)));
            } else if (tool === 'bookmark' && selectedMap) {
              const bm: Bookmark = {
                id: uuidv4(),
                name: `BM ${bookmarks.length + 1}`,
                ...withYaw,
              };
              setBookmarksForMap(selectedMap, [...bookmarks, bm]);
            } else if (tool === 'waypoint') {
              setDraftWaypoints((items) => [
                ...items,
                {
                  id: uuidv4(),
                  type: 'goto',
                  name: `WP ${items.length + 1}`,
                  position: withYaw,
                },
              ]);
            }
          }}
        />
        <WaypointPanel
          mapName={selectedMap ?? ''}
          draftWaypoints={draftWaypoints}
          onClearDraft={() => setDraftWaypoints([])}
        />
      </div>

      {showCamera && (
        <div className="camera-overlay">
          <ImageViewer
            ros={ros}
            topic={settings.cameraImageTopic}
            enabled={settings.cameraEnabled}
          />
        </div>
      )}

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

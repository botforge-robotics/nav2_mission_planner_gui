import { useEffect, useRef } from 'react';
import { Joystick } from '../components/Joystick';
import { ImageViewer } from '../components/ImageViewer';
import { createPublisher } from '../ros/Ros2Client';
import { useConnectionStore } from '../stores/connectionStore';
import { useSettingsStore } from '../stores/settingsStore';

export function TeleopScreen() {
  const ros = useConnectionStore((s) => s.ros);
  const settings = useSettingsStore((s) => s.settings);
  const pubRef = useRef<ReturnType<typeof createPublisher> | null>(null);

  useEffect(() => {
    if (!ros) return;
    pubRef.current = createPublisher(ros, settings.cmdVelTopic, settings.twistType);
    return () => {
      pubRef.current?.shutdown();
      pubRef.current = null;
    };
  }, [ros, settings.cmdVelTopic, settings.twistType]);

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

  return (
    <div className="teleop-screen">
      <ImageViewer
        ros={ros}
        topic={settings.cameraImageTopic}
        enabled={settings.cameraEnabled && settings.cameraVisible}
      />
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

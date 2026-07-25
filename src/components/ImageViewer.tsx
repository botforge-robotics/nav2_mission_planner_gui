import { useEffect, useState } from 'react';
import { createSubscriber, type Ros2Client } from '../ros/Ros2Client';

interface Props {
  ros: Ros2Client | null;
  topic: string;
  enabled?: boolean;
}

export function ImageViewer({ ros, topic, enabled = true }: Props) {
  const [src, setSrc] = useState<string | null>(null);

  useEffect(() => {
    if (!ros || !enabled || !topic) {
      setSrc(null);
      return;
    }
    const sub = createSubscriber(
      ros,
      topic,
      'sensor_msgs/msg/CompressedImage',
      (msg) => {
        const data = msg.data as string;
        const format = String(msg.format ?? 'jpeg');
        const mime = format.includes('png') ? 'image/png' : 'image/jpeg';
        setSrc(`data:${mime};base64,${data}`);
      },
    );
    return () => sub.shutdown();
  }, [ros, topic, enabled]);

  if (!enabled || !topic) {
    return <div className="image-viewer empty">Camera disabled</div>;
  }

  return (
    <div className="image-viewer">
      {src ? <img src={src} alt="camera" /> : <div className="empty">Waiting for image…</div>}
    </div>
  );
}

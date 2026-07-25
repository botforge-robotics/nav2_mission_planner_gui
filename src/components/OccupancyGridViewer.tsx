import { useCallback, useEffect, useRef, useState } from 'react';
import { createSubscriber, type Ros2Client } from '../ros/Ros2Client';
import type { Bookmark } from '../models/bookmark';
import type { MissionItem } from '../models/mission';
import { theme } from '../constants/theme';

export interface Pose2D {
  x: number;
  y: number;
  theta: number;
}

interface Props {
  ros: Ros2Client | null;
  mapTopic?: string;
  useStaticMap?: boolean;
  robotPose?: Pose2D | null;
  path?: Array<{ x: number; y: number }>;
  bookmarks?: Bookmark[];
  missionItems?: MissionItem[];
  goalPose?: Pose2D | null;
  onMapClick?: (pose: Pose2D) => void;
  onMapLongPress?: (pose: Pose2D) => void;
  tool?: 'none' | 'localize' | 'goal' | 'bookmark' | 'waypoint';
}

interface OccupancyGrid {
  width: number;
  height: number;
  resolution: number;
  originX: number;
  originY: number;
  originYaw: number;
  data: number[];
}

function parseGrid(msg: Record<string, unknown>): OccupancyGrid | null {
  const info = msg.info as Record<string, unknown> | undefined;
  const data = msg.data as number[] | undefined;
  if (!info || !data) return null;
  const origin = info.origin as Record<string, unknown>;
  const pos = origin.position as Record<string, number>;
  const ori = origin.orientation as Record<string, number>;
  const yaw = Math.atan2(
    2 * (ori.w * ori.z + ori.x * ori.y),
    1 - 2 * (ori.y * ori.y + ori.z * ori.z),
  );
  return {
    width: Number(info.width),
    height: Number(info.height),
    resolution: Number(info.resolution),
    originX: pos.x,
    originY: pos.y,
    originYaw: yaw,
    data,
  };
}

function worldToPixel(grid: OccupancyGrid, x: number, y: number) {
  const dx = x - grid.originX;
  const dy = y - grid.originY;
  const c = Math.cos(-grid.originYaw);
  const s = Math.sin(-grid.originYaw);
  const mx = c * dx - s * dy;
  const my = s * dx + c * dy;
  return {
    px: mx / grid.resolution,
    py: grid.height - my / grid.resolution,
  };
}

function pixelToWorld(grid: OccupancyGrid, px: number, py: number) {
  const mx = px * grid.resolution;
  const my = (grid.height - py) * grid.resolution;
  const c = Math.cos(grid.originYaw);
  const s = Math.sin(grid.originYaw);
  return {
    x: grid.originX + c * mx - s * my,
    y: grid.originY + s * mx + c * my,
  };
}

export function OccupancyGridViewer({
  ros,
  mapTopic = '/map',
  robotPose,
  path = [],
  bookmarks = [],
  missionItems = [],
  goalPose,
  onMapClick,
  tool = 'none',
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [grid, setGrid] = useState<OccupancyGrid | null>(null);
  const [scale, setScale] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const drag = useRef<{ x: number; y: number } | null>(null);

  useEffect(() => {
    if (!ros) return;
    const sub = createSubscriber(ros, mapTopic, 'nav_msgs/msg/OccupancyGrid', (msg) => {
      const g = parseGrid(msg);
      if (g) setGrid(g);
    });
    return () => sub.shutdown();
  }, [ros, mapTopic]);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || !grid) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const { width, height, data } = grid;
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    const img = ctx.createImageData(width, height);
    for (let i = 0; i < data.length; i++) {
      const v = data[i];
      let c = 128;
      if (v === 0) c = 255;
      else if (v === 100) c = 0;
      else if (v < 0) c = 80;
      else c = 255 - Math.round((v / 100) * 255);
      const o = i * 4;
      img.data[o] = c;
      img.data[o + 1] = c;
      img.data[o + 2] = c;
      img.data[o + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);

    const strokePose = (pose: Pose2D, color: string, size = 8) => {
      const p = worldToPixel(grid, pose.x, pose.y);
      ctx.save();
      ctx.translate(p.px, p.py);
      ctx.rotate(-pose.theta);
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.moveTo(size, 0);
      ctx.lineTo(-size * 0.6, size * 0.6);
      ctx.lineTo(-size * 0.6, -size * 0.6);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    };

    if (path.length > 1) {
      ctx.strokeStyle = theme.brand;
      ctx.lineWidth = 2;
      ctx.beginPath();
      path.forEach((pt, i) => {
        const p = worldToPixel(grid, pt.x, pt.y);
        if (i === 0) ctx.moveTo(p.px, p.py);
        else ctx.lineTo(p.px, p.py);
      });
      ctx.stroke();
    }

    bookmarks.forEach((b) => {
      strokePose({ x: b.x, y: b.y, theta: b.theta }, '#9c27b0', 7);
    });

    missionItems
      .filter((i) => i.type === 'goto' && i.position)
      .forEach((i, idx) => {
        const p = worldToPixel(grid, i.position!.x, i.position!.y);
        ctx.fillStyle = '#2196f3';
        ctx.beginPath();
        ctx.arc(p.px, p.py, 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = '#fff';
        ctx.font = '10px sans-serif';
        ctx.fillText(String(idx + 1), p.px + 6, p.py - 6);
      });

    if (goalPose) strokePose(goalPose, '#43a047', 10);
    if (robotPose) strokePose(robotPose, theme.brand, 10);
  }, [grid, robotPose, path, bookmarks, missionItems, goalPose]);

  useEffect(() => {
    draw();
  }, [draw]);

  const toWorldFromEvent = (e: React.MouseEvent) => {
    if (!grid || !canvasRef.current) return null;
    const rect = canvasRef.current.getBoundingClientRect();
    const px = (e.clientX - rect.left - offset.x) / scale;
    const py = (e.clientY - rect.top - offset.y) / scale;
    const w = pixelToWorld(grid, px, py);
    return { x: w.x, y: w.y, theta: 0 };
  };

  return (
    <div
      className="map-viewer"
      onWheel={(e) => {
        e.preventDefault();
        setScale((s) => Math.min(8, Math.max(0.2, s * (e.deltaY > 0 ? 0.9 : 1.1))));
      }}
      onMouseDown={(e) => {
        if (e.button === 0 && tool === 'none') {
          drag.current = { x: e.clientX - offset.x, y: e.clientY - offset.y };
        }
      }}
      onMouseMove={(e) => {
        if (drag.current) {
          setOffset({
            x: e.clientX - drag.current.x,
            y: e.clientY - drag.current.y,
          });
        }
      }}
      onMouseUp={(e) => {
        if (drag.current) {
          drag.current = null;
          return;
        }
        const pose = toWorldFromEvent(e);
        if (pose && onMapClick && tool !== 'none') onMapClick(pose);
      }}
      onMouseLeave={() => {
        drag.current = null;
      }}
    >
      {!grid && <div className="map-empty">Waiting for map…</div>}
      <canvas
        ref={canvasRef}
        style={{
          transform: `translate(${offset.x}px, ${offset.y}px) scale(${scale})`,
          transformOrigin: '0 0',
        }}
      />
    </div>
  );
}

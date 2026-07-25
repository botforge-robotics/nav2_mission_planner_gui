import { useRef } from 'react';

interface Props {
  onMove: (linear: number, angular: number) => void;
  onStop: () => void;
  maxLinear: number;
  maxAngular: number;
  visible?: boolean;
}

export function Joystick({
  onMove,
  onStop,
  maxLinear,
  maxAngular,
  visible = true,
}: Props) {
  const active = useRef(false);
  const rootRef = useRef<HTMLDivElement>(null);

  if (!visible) return null;

  const handle = (clientX: number, clientY: number) => {
    const el = rootRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    const dx = (clientX - cx) / (rect.width / 2);
    const dy = (clientY - cy) / (rect.height / 2);
    const mag = Math.min(1, Math.hypot(dx, dy));
    const nx = mag ? (dx / Math.hypot(dx, dy)) * mag : 0;
    const ny = mag ? (dy / Math.hypot(dx, dy)) * mag : 0;
    onMove(-ny * maxLinear, -nx * maxAngular);
  };

  return (
    <div
      className="joystick"
      ref={rootRef}
      onPointerDown={(e) => {
        active.current = true;
        (e.target as HTMLElement).setPointerCapture(e.pointerId);
        handle(e.clientX, e.clientY);
      }}
      onPointerMove={(e) => {
        if (!active.current) return;
        handle(e.clientX, e.clientY);
      }}
      onPointerUp={() => {
        active.current = false;
        onStop();
      }}
      onPointerCancel={() => {
        active.current = false;
        onStop();
      }}
    >
      <div className="joystick-knob" />
    </div>
  );
}

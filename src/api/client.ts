async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const url = path.startsWith('/api') ? path : `/api${path.startsWith('/') ? path : `/${path}`}`;
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...(init?.headers || {}) },
    ...init,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || res.statusText);
  }
  return res.json() as Promise<T>;
}

export interface ClaimedRobot {
  id: string;
  name: string;
  ip: string;
  port: string;
  claimedAt?: number;
}

export interface NearbyRobot {
  id: string;
  name: string;
  ip: string;
  port: string;
  last_seen: number;
  source: string;
}

export const api = {
  health: () => req<{ ok: boolean }>('/api/health'),
  getClaim: () => req<ClaimedRobot | null>('/api/claim'),
  claim: (body: { name?: string; ip: string; port?: string; id?: string }) =>
    req<{ robot: ClaimedRobot; online: boolean }>('/api/claim', {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  unclaim: () => req<{ ok: boolean }>('/api/claim', { method: 'DELETE' }),
  heartbeat: () =>
    req<{
      claimed: boolean;
      online: boolean;
      robot?: ClaimedRobot;
      checkedAt: number;
    }>('/api/heartbeat'),
  nearby: (scan = true) =>
    req<{ robots: NearbyRobot[]; scannedAt: number }>(
      `/api/nearby?scan=${scan ? '1' : '0'}`,
    ),
  getSettings: () => req<Record<string, unknown>>('/api/settings'),
  putSettings: (settings: Record<string, unknown>) =>
    req<Record<string, unknown>>('/api/settings', {
      method: 'PUT',
      body: JSON.stringify(settings),
    }),
};

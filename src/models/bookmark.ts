export interface Bookmark {
  id: string;
  name: string;
  x: number;
  y: number;
  theta: number;
}

export function bookmarkFromJson(json: Record<string, unknown>): Bookmark {
  return {
    id: String(json.id ?? ''),
    name: String(json.name ?? ''),
    x: Number(json.x ?? 0),
    y: Number(json.y ?? 0),
    theta: Number(json.theta ?? 0),
  };
}

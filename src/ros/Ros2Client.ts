export type RosStatus =
  | 'none'
  | 'connecting'
  | 'connected'
  | 'closed'
  | 'errored';

export type RosMessageHandler = (data: Record<string, unknown>) => void;

export class Ros2Client {
  url: string;
  status: RosStatus = 'none';
  private ws: WebSocket | null = null;
  private callers = 0;
  private statusListeners = new Set<(s: RosStatus) => void>();
  private messageListeners = new Set<RosMessageHandler>();

  constructor(url = '') {
    this.url = url;
  }

  onStatus(listener: (s: RosStatus) => void): () => void {
    this.statusListeners.add(listener);
    return () => this.statusListeners.delete(listener);
  }

  onMessage(listener: RosMessageHandler): () => void {
    this.messageListeners.add(listener);
    return () => this.messageListeners.delete(listener);
  }

  private setStatus(status: RosStatus) {
    this.status = status;
    this.statusListeners.forEach((l) => l(status));
  }

  connect(url?: string): void {
    if (url) this.url = url;
    this.setStatus('connecting');
    try {
      this.ws = new WebSocket(this.url);
      this.ws.onopen = () => this.setStatus('connected');
      this.ws.onerror = () => this.setStatus('errored');
      this.ws.onclose = () => this.setStatus('closed');
      this.ws.onmessage = (ev) => {
        try {
          const data = JSON.parse(String(ev.data)) as Record<string, unknown>;
          this.messageListeners.forEach((l) => l(data));
        } catch {
          /* ignore malformed */
        }
      };
    } catch {
      this.setStatus('errored');
    }
  }

  close(): void {
    this.ws?.close();
    this.ws = null;
    this.setStatus('closed');
  }

  send(message: unknown): boolean {
    if (this.status !== 'connected' || !this.ws) return false;
    const payload =
      typeof message === 'string' ? message : JSON.stringify(message);
    this.ws.send(payload);
    return true;
  }

  requestServiceCaller(serviceName: string): string {
    return `service_request:${serviceName}:${this.callers++}`;
  }

  requestActionCaller(): string {
    return crypto.randomUUID();
  }
}

export function createPublisher(
  ros: Ros2Client,
  topic: string,
  type: string,
) {
  ros.send({ op: 'advertise', topic, type });
  return {
    publish(msg: Record<string, unknown>) {
      ros.send({ op: 'publish', topic, msg });
    },
    shutdown() {
      ros.send({ op: 'unadvertise', topic });
    },
  };
}

export function createSubscriber(
  ros: Ros2Client,
  topic: string,
  type: string,
  callback: (msg: Record<string, unknown>) => void,
) {
  ros.send({ op: 'subscribe', topic, type });
  const unsub = ros.onMessage((data) => {
    if (data.op === 'publish' && data.topic === topic) {
      callback(data.msg as Record<string, unknown>);
    }
  });
  return {
    shutdown() {
      ros.send({ op: 'unsubscribe', topic, type });
      unsub();
    },
  };
}

export async function callService(
  ros: Ros2Client,
  service: string,
  type: string,
  args: Record<string, unknown>,
  timeoutSec = 120,
): Promise<Record<string, unknown>> {
  const id = ros.requestServiceCaller(service);
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      cleanup();
      reject(new Error(`Service ${service} timed out`));
    }, timeoutSec * 1000);

    const cleanup = ros.onMessage((message) => {
      if (
        message.op === 'service_response' &&
        message.service === service &&
        message.id === id
      ) {
        window.clearTimeout(timer);
        cleanup();
        if (message.result !== true) {
          reject(message.values ?? new Error('Service call failed'));
        } else {
          resolve((message.values as Record<string, unknown>) ?? {});
        }
      }
    });

    ros.send({
      op: 'call_service',
      id,
      service,
      type,
      args,
      timeout: timeoutSec,
    });
  });
}

export interface ActionGoalHandle {
  goalId: string;
  result: Promise<Record<string, unknown>>;
  cancel: () => void;
}

export function sendActionGoal(
  ros: Ros2Client,
  action: string,
  actionType: string,
  args: Record<string, unknown>,
  onFeedback?: (values: Record<string, unknown>) => void,
): ActionGoalHandle {
  const goalId = ros.requestActionCaller();
  let resolveResult!: (v: Record<string, unknown>) => void;
  let rejectResult!: (e: unknown) => void;
  const result = new Promise<Record<string, unknown>>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  const unsub = ros.onMessage((message) => {
    if (message.action !== action || message.id !== goalId) return;
    if (message.op === 'action_feedback' && onFeedback) {
      onFeedback((message.values as Record<string, unknown>) ?? {});
    }
    if (message.op === 'action_result') {
      unsub();
      const status = message.status;
      if (status !== 4) {
        rejectResult(message.values ?? new Error('Action failed'));
      } else {
        resolveResult((message.values as Record<string, unknown>) ?? {});
      }
    }
  });

  ros.send({
    op: 'send_action_goal',
    id: goalId,
    action,
    feedback: Boolean(onFeedback),
    action_type: actionType,
    args,
  });

  return {
    goalId,
    result,
    cancel() {
      ros.send({
        op: 'cancel_action_goal',
        id: goalId,
        action,
      });
    },
  };
}

/** TCP-style reachability probe via WebSocket attempt (browser cannot raw TCP). */
export async function probeRosbridge(
  ip: string,
  port: string,
  timeoutMs = 3000,
): Promise<boolean> {
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://${ip}:${port}`);
    const timer = window.setTimeout(() => {
      ws.close();
      resolve(false);
    }, timeoutMs);
    ws.onopen = () => {
      window.clearTimeout(timer);
      ws.close();
      resolve(true);
    };
    ws.onerror = () => {
      window.clearTimeout(timer);
      resolve(false);
    };
  });
}

import type { Mission, MissionItem } from '../models/mission';
import {
  callService,
  createPublisher,
  createSubscriber,
  sendActionGoal,
  type Ros2Client,
} from '../ros/Ros2Client';
import { createGoalService } from './goalService';

export interface MissionProgress {
  mission: Mission;
  currentIndex: number;
  isRunning: boolean;
  isPaused: boolean;
  errorMessage?: string;
}

type Listener = (p: MissionProgress) => void;

export class MissionExecutionService {
  private mission: Mission | null = null;
  private currentIndex = 0;
  private isRunning = false;
  private isPaused = false;
  private error: string | undefined;
  private listeners = new Set<Listener>();
  private cancelFlag = false;
  private publishTimers: number[] = [];
  private goalService: ReturnType<typeof createGoalService> | null = null;

  onProgress(listener: Listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private broadcast() {
    if (!this.mission) return;
    const progress: MissionProgress = {
      mission: this.mission,
      currentIndex: this.currentIndex,
      isRunning: this.isRunning,
      isPaused: this.isPaused,
      errorMessage: this.error,
    };
    this.listeners.forEach((l) => l(progress));
  }

  get running() {
    return this.isRunning;
  }

  pause() {
    this.isPaused = true;
    this.broadcast();
  }

  resume() {
    this.isPaused = false;
    this.broadcast();
  }

  cancel() {
    this.cancelFlag = true;
    this.isRunning = false;
    this.isPaused = false;
    this.goalService?.cancel();
    this.publishTimers.forEach((t) => window.clearInterval(t));
    this.publishTimers = [];
    this.broadcast();
  }

  async start(
    ros: Ros2Client,
    mission: Mission,
    cameraTopic?: string,
  ): Promise<void> {
    if (this.isRunning) return;
    this.mission = mission;
    this.currentIndex = 0;
    this.isRunning = true;
    this.isPaused = false;
    this.error = undefined;
    this.cancelFlag = false;
    this.goalService = createGoalService(ros);
    this.broadcast();

    try {
      while (
        this.isRunning &&
        !this.cancelFlag &&
        this.currentIndex < mission.items.length
      ) {
        while (this.isPaused && this.isRunning && !this.cancelFlag) {
          await sleep(200);
        }
        if (!this.isRunning || this.cancelFlag) break;
        const item = mission.items[this.currentIndex];
        const ok = await this.executeItem(ros, item, cameraTopic);
        if (!ok) {
          this.error = `Failed at item ${this.currentIndex + 1}`;
          break;
        }
        this.currentIndex += 1;
        this.broadcast();
      }
    } catch (e) {
      this.error = e instanceof Error ? e.message : String(e);
    } finally {
      this.isRunning = false;
      this.broadcast();
    }
  }

  private async executeItem(
    ros: Ros2Client,
    item: MissionItem,
    cameraTopic?: string,
  ): Promise<boolean> {
    switch (item.type) {
      case 'goto': {
        if (!item.position) return false;
        await this.goalService!.navigateToPose(
          item.position.x,
          item.position.y,
          item.position.theta,
        );
        return true;
      }
      case 'wait': {
        const ms = (item.waitDuration ?? 1) * 1000;
        await sleep(ms);
        return true;
      }
      case 'publish': {
        if (!item.publishTopic || !item.publishMsgType) return false;
        const pub = createPublisher(
          ros,
          item.publishTopic,
          item.publishMsgType,
        );
        const msg = item.publishMessage ?? {};
        const freqType = item.publishFrequencyType ?? 'once';
        if (freqType === 'once') {
          pub.publish(msg);
        } else if (freqType === 'hz') {
          const hz = item.publishFrequency ?? 1;
          const duration = (item.publishDuration ?? 1) * 1000;
          await new Promise<void>((resolve) => {
            const id = window.setInterval(() => pub.publish(msg), 1000 / hz);
            this.publishTimers.push(id);
            window.setTimeout(() => {
              window.clearInterval(id);
              resolve();
            }, duration);
          });
        } else if (freqType === 'duration') {
          const duration = (item.publishDuration ?? 1) * 1000;
          const id = window.setInterval(() => pub.publish(msg), 100);
          this.publishTimers.push(id);
          await sleep(duration);
          window.clearInterval(id);
        } else {
          pub.publish(msg);
        }
        return true;
      }
      case 'callService': {
        if (!item.serviceName || !item.serviceType) return false;
        await callService(
          ros,
          item.serviceName,
          item.serviceType,
          item.serviceRequest ?? {},
        );
        return true;
      }
      case 'callAction': {
        if (!item.actionName || !item.actionType) return false;
        const handle = sendActionGoal(
          ros,
          item.actionName,
          item.actionType,
          item.actionGoal ?? {},
        );
        if (item.waitForActionResult !== false) {
          await handle.result;
        }
        return true;
      }
      case 'captureImage': {
        if (!cameraTopic) return true;
        await new Promise<void>((resolve) => {
          const sub = createSubscriber(
            ros,
            cameraTopic,
            'sensor_msgs/msg/CompressedImage',
            (msg) => {
              try {
                const data = msg.data as string;
                const link = document.createElement('a');
                link.href = `data:image/jpeg;base64,${data}`;
                link.download = `capture_${Date.now()}.jpg`;
                link.click();
              } finally {
                sub.shutdown();
                resolve();
              }
            },
          );
          window.setTimeout(() => {
            sub.shutdown();
            resolve();
          }, 5000);
        });
        return true;
      }
      default:
        return false;
    }
  }
}

function sleep(ms: number) {
  return new Promise((r) => window.setTimeout(r, ms));
}

export const missionExecutor = new MissionExecutionService();

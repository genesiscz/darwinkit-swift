export type DarwinKitEvent =
  | { type: "ready"; version: string; capabilities: string[] }
  | { type: "filesChanged"; paths: string[] }
  | { type: "llmChunk"; request_id: string; chunk: string }
  | {
      type: "notificationInteraction";
      notification_identifier: string;
      action_identifier: string;
      user_text?: string;
      user_info: Record<string, unknown>;
      category_identifier: string;
    }
  | { type: "reconnect"; attempt: number }
  | { type: "disconnect"; code: number | null }
  | { type: "error"; error: Error };

export interface EventMap {
  ready: { version: string; capabilities: string[] };
  filesChanged: { paths: string[] };
  llmChunk: { request_id: string; chunk: string };
  notificationInteraction: {
    notification_identifier: string;
    action_identifier: string;
    user_text?: string;
    user_info: Record<string, unknown>;
    category_identifier: string;
  };
  reconnect: { attempt: number };
  disconnect: { code: number | null };
  error: { error: Error };
}

export type EventType = keyof EventMap;

/**
 * Typed wrapper for browser.runtime.sendMessage to/from the background.
 */

import type {
  ExtensionMessage,
  ExtensionMessageResponse,
  MessageType,
} from "../shared/types";

export async function sendMessage<T = unknown>(
  type: MessageType,
  payload?: unknown
): Promise<T> {
  const requestId = crypto.randomUUID();
  const message: ExtensionMessage = { type, requestId, payload };
  const response: ExtensionMessageResponse<T> = await browser.runtime.sendMessage(message);
  if (!response.success) {
    throw response.error ?? { code: "UNKNOWN", message: "Unknown error", recoverable: false };
  }
  return response.data as T;
}

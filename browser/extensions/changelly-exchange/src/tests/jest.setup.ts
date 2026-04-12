import { jest } from "@jest/globals";

// Stub browser extension APIs not available in jsdom.
(globalThis as any).browser = {
  runtime: {
    sendMessage: jest.fn(),
    getManifest: jest.fn().mockReturnValue({ version: "1.0.0" }),
  },
  storage: {
    local: {
      get: jest.fn(async () => ({})),
      set: jest.fn(async () => undefined),
    },
  },
  alarms: {
    create: jest.fn(),
    clear: jest.fn(),
    onAlarm: { addListener: jest.fn() },
  },
  notifications: {
    create: jest.fn(),
  },
};

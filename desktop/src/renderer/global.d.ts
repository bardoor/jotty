export {};

declare global {
  interface Window {
    jotty: {
      websocketUrl: string;
      pickContextDirectory(): Promise<{ path: string; approval: string } | null>;
      setAlwaysOnTop(enabled: boolean): void;
      openExternal(url: string): void;
    };
  }
}

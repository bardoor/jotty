export {};

declare global {
  interface Window {
    jotty: {
      websocketUrl: string;
    };
  }
}

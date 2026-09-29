import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  base: "./",
  plugins: [react()],
  root: "src/renderer",
  build: {
    outDir: "../../dist/renderer",
    emptyOutDir: true
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true
  },
  test: {
    environment: "jsdom",
    include: ["**/*.test.ts", "**/*.test.tsx", "../main/**/*.test.ts"]
  }
});

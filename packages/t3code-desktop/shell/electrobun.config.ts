import type { ElectrobunConfig } from "electrobun";

// Minimal Electrobun shell wrapping a local t3code server.
// CEF is disabled on all platforms -- we use the system webview
// (webkit2gtk-4.1 on Linux) which keeps the bundle size small.
export default {
  app: {
    name: "t3code-desktop",
    identifier: "sh.blackboard.t3code-desktop",
    version: "0.0.1",
  },
  build: {
    bun: {
      entrypoint: "src/bun/index.ts",
    },
    views: {},
    linux: { bundleCEF: false },
    mac: { bundleCEF: false },
    win: { bundleCEF: false },
  },
} satisfies ElectrobunConfig;

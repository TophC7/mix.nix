// T3 Code desktop shell
//
// Spawns the `t3` CLI as a child process, waits for its HTTP server to start
// listening, then opens an Electrobun window pointed at it. Kills the child
// on shutdown so closing the window cleanly tears everything down.
//
// Config via env vars:
//   T3CODE_DESKTOP_BIN   - path to the `t3` executable (defaults to "t3")
//   T3CODE_DESKTOP_PORT  - port to bind (defaults to a fixed local port)
//   T3CODE_DESKTOP_HOST  - host to bind (defaults to 127.0.0.1)

import { spawn } from "bun";
import { BrowserWindow } from "electrobun/bun";

const t3Bin = process.env["T3CODE_DESKTOP_BIN"] ?? "t3";
const port = Number(process.env["T3CODE_DESKTOP_PORT"] ?? "18822");
const host = process.env["T3CODE_DESKTOP_HOST"] ?? "127.0.0.1";

// Optional parent-death exec shim provided by the Nix derivation (a tiny C
// binary that calls prctl(PR_SET_PDEATHSIG, SIGTERM) before execvp'ing its
// target). Wrapping t3 in this shim ensures the kernel kills it the
// instant we (its direct parent) die -- even if Electrobun's GTK FFI loop
// has blocked signal delivery in our own JS event loop, which prevents
// process.on("SIGTERM", ...) from firing reliably.
const pdeathExec = process.env["T3CODE_DESKTOP_PDEATH_EXEC"];

// Start the server. --no-browser keeps it from opening the user's default
// browser -- we'll show the UI in our own window instead.
const t3Cmd = ["--no-browser", "--port", String(port), "--host", host];
const t3Proc = spawn({
	cmd: pdeathExec
		? [pdeathExec, t3Bin, ...t3Cmd]
		: [t3Bin, ...t3Cmd],
	stdout: "inherit",
	stderr: "inherit",
});

// Poll the TCP port until it accepts connections. Electrobun's webview will
// hit a "refused" error if we open the window before t3 is ready.
async function waitForPort(
	h: string,
	p: number,
	timeoutMs: number,
): Promise<void> {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		try {
			const sock = await Bun.connect({
				hostname: h,
				port: p,
				socket: {
					data() {},
					open(s) {
						s.end();
					},
					error() {},
				},
			});
			sock.end();
			return;
		} catch {
			await Bun.sleep(100);
		}
	}
	throw new Error(
		`t3 did not start listening on ${h}:${p} within ${timeoutMs}ms`,
	);
}

try {
	await waitForPort(host, port, 15000);
} catch (err) {
	console.error("[t3code-desktop]", err);
	t3Proc.kill();
	process.exit(1);
}

// Clean-shutdown path (window close / Electrobun quit()): fire an explicit
// kill on the child so we don't leak it while the process is still
// responsive. When control never returns to JS (launcher killed externally,
// Electrobun FFI loop blocking), none of these handlers fire -- the
// pdeath-exec wrapper handles that case at the kernel level by killing the
// t3 child as soon as bun exits.
const cleanup = () => {
	try {
		t3Proc.kill();
	} catch {}
};
process.on("exit", cleanup);
process.on("SIGINT", () => {
	cleanup();
	process.exit(130);
});
process.on("SIGTERM", () => {
	cleanup();
	process.exit(143);
});
process.on("SIGHUP", () => {
	cleanup();
	process.exit(129);
});

new BrowserWindow({
	title: "T3 Code",
	url: `http://${host}:${port}`,
	frame: {
		x: 100,
		y: 100,
		width: 1200,
		height: 800,
	},
});

console.log(`[t3code-desktop] opened window at http://${host}:${port}`);

// T3 Code desktop shell.
//
// Spawns the `t3` CLI as a child process, waits for its HTTP server to
// actually serve a response (not just accept TCP), then opens an Electrobun
// window pointed at it.
//
// Two subtleties that are easy to get wrong:
//
//   1. TCP accept readiness is not enough. `net.listen()` accepts
//      connections before route handlers are mounted, so opening the
//      webview during that window results in a permanent white screen.
//      We do an actual HTTP GET and require a <500 response.
//
//   2. Electrobun's GTK FFI loop blocks JS signal delivery, so
//      `process.on("SIGTERM", ...)` can't be relied on for child cleanup.
//      The Nix derivation ships a tiny `pdeath-exec` C shim that calls
//      prctl(PR_SET_PDEATHSIG, SIGTERM) before execvp'ing t3, so the
//      kernel tears down the child the instant bun dies. We opt into it
//      via T3CODE_DESKTOP_PDEATH_EXEC.
//
// Env vars:
//   T3CODE_DESKTOP_BIN          - path to the `t3` executable (default "t3")
//   T3CODE_DESKTOP_PORT         - port to bind (default 18822)
//   T3CODE_DESKTOP_HOST         - host to bind (default 127.0.0.1)
//   T3CODE_DESKTOP_PDEATH_EXEC  - optional pdeath-exec shim path

import { spawn } from "bun";
import { BrowserWindow } from "electrobun/bun";

const t3Bin = process.env["T3CODE_DESKTOP_BIN"] ?? "t3";
const host = process.env["T3CODE_DESKTOP_HOST"] ?? "127.0.0.1";

const portRaw = process.env["T3CODE_DESKTOP_PORT"] ?? "18822";
const port = Number(portRaw);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
	console.error(
		`[t3code-desktop] T3CODE_DESKTOP_PORT must be an integer in [1,65535], got: ${portRaw}`,
	);
	process.exit(2);
}

const pdeathExec = process.env["T3CODE_DESKTOP_PDEATH_EXEC"];

const baseCmd = [t3Bin, "--no-browser", "--port", String(port), "--host", host];
const t3Proc = spawn({
	cmd: pdeathExec ? [pdeathExec, ...baseCmd] : baseCmd,
	stdout: "inherit",
	stderr: "inherit",
});

// Retry on transient network errors while the server is booting. Bun uses
// symbolic codes without glibc's `E` prefix ("ConnectionRefused"); Node uses
// the glibc names ("ECONNREFUSED"); accept both.
const RETRIABLE_CODES = new Set([
	"ConnectionRefused",
	"ConnectionReset",
	"ConnectionClosed",
	"CanceledRequest",
	"ECONNREFUSED",
	"ECONNRESET",
	"ENOTFOUND",
	"ETIMEDOUT",
]);
const RETRIABLE_NAMES = new Set(["TimeoutError", "AbortError"]);

function isRetriableFetchError(err: unknown): boolean {
	if (!(err instanceof Error)) return false;
	const code = (err as NodeJS.ErrnoException).code;
	if (code && RETRIABLE_CODES.has(code)) return true;
	if (RETRIABLE_NAMES.has(err.name)) return true;
	// Bun sometimes throws a plain `TypeError: fetch failed` with no code.
	// Narrow on the message so real TypeErrors from buggy code aren't
	// silently treated as "still booting".
	return err.name === "TypeError" && /fetch failed/i.test(err.message);
}

// Require two consecutive successful probes: the first proves routes are
// mounted, the second closes a small window where the server answers once
// and then blocks (e.g. a slow middleware warming up).
async function waitForHttp(
	baseUrl: string,
	timeoutMs: number,
): Promise<void> {
	const deadline = Date.now() + timeoutMs;
	let consecutiveOk = 0;
	const required = 2;

	while (Date.now() < deadline) {
		try {
			const res = await fetch(baseUrl, {
				signal: AbortSignal.timeout(1000),
				redirect: "manual", // a redirect still counts as "server is up"
			});
			res.body?.cancel();
			if (res.status < 500) {
				consecutiveOk += 1;
				if (consecutiveOk >= required) return;
				continue;
			}
			consecutiveOk = 0;
		} catch (err) {
			if (!isRetriableFetchError(err)) throw err;
			consecutiveOk = 0;
		}
		await Bun.sleep(100);
	}
	throw new Error(
		`t3 did not become ready at ${baseUrl} within ${timeoutMs}ms`,
	);
}

const baseUrl = `http://${host}:${port}`;

// Race the HTTP-readiness probe against the subprocess's own exit promise.
// If t3 crashes at startup (bad flag, port in use, internal error) we'd
// otherwise poll for the full timeout and then open a window at a dead server.
type ReadyResult = { kind: "ready" } | { kind: "exited"; code: number | null };
try {
	const result: ReadyResult = await Promise.race([
		waitForHttp(baseUrl, 15000).then(() => ({ kind: "ready" as const })),
		t3Proc.exited.then((code) => ({ kind: "exited" as const, code })),
	]);
	if (result.kind === "exited") {
		console.error(
			`[t3code-desktop] t3 exited before becoming ready (code ${result.code})`,
		);
		process.exit(1);
	}
} catch (err) {
	console.error("[t3code-desktop]", err);
	try {
		t3Proc.kill();
	} catch {
		/* already exited */
	}
	process.exit(1);
}

// Belt-and-suspenders for the rare case where JS IS still running on
// shutdown (window close / Electrobun quit()). The usual kill path is
// pdeath-exec at the kernel level -- see header.
const cleanup = () => {
	try {
		t3Proc.kill();
	} catch {
		/* already exited */
	}
};
const signalExitCodes: Record<string, number> = {
	SIGINT: 130,
	SIGTERM: 143,
	SIGHUP: 129,
};
for (const [sig, code] of Object.entries(signalExitCodes)) {
	process.on(sig, () => {
		cleanup();
		process.exit(code);
	});
}

new BrowserWindow({
	title: "T3 Code",
	url: baseUrl,
	frame: {
		x: 100,
		y: 100,
		width: 1200,
		height: 800,
	},
});

console.log(`[t3code-desktop] opened window at ${baseUrl}`);

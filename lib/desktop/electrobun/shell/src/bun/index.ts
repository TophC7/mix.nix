// Generic Electrobun shell for mkElectrobunApp-generated applications.
//
// Reads src/bun/config.json (generated at Nix build time) to determine:
//   mode "url"     — open a window at an external URL (self-hosted services)
//   mode "command" — spawn a child process, wait for readiness, open window
//
// See lib/desktop/electrobun/ in mix.nix for the Nix-side builder.
//
// CLAUDE: config.json is generated at Nix build time — do not create manually

import { spawn, type Subprocess } from "bun";
import { BrowserWindow } from "electrobun/bun";
import config from "./config.json";

// ── Config types (discriminated union matching Nix-generated JSON) ───────────

interface SharedConfig {
	title: string;
	window: { width: number; height: number };
	readinessTimeoutMs: number;
	envPrefix: string;
}

interface UrlConfig extends SharedConfig {
	mode: "url";
	url: {
		default: string;
		envVar: string;
	};
}

interface CommandConfig extends SharedConfig {
	mode: "command";
	command: {
		binEnvVar: string;
		args: string[];
		portDefault: number;
		portEnvVar: string;
		hostDefault: string;
		hostEnvVar: string;
		cwdEnvVar: string;
		pdeathExecEnvVar: string;
	};
}

type AppConfig = UrlConfig | CommandConfig;

function validateConfig(raw: unknown): AppConfig {
	const c = raw as Record<string, unknown>;
	if (c.mode !== "url" && c.mode !== "command") {
		throw new Error(`Invalid config: mode must be "url" or "command", got "${c.mode}"`);
	}
	if (c.mode === "url" && (!c.url || typeof (c.url as Record<string, unknown>).default !== "string")) {
		throw new Error("Invalid config: url mode requires url.default");
	}
	if (c.mode === "command" && (!c.command || typeof (c.command as Record<string, unknown>).binEnvVar !== "string")) {
		throw new Error("Invalid config: command mode requires command.binEnvVar");
	}
	return c as AppConfig;
}

const cfg = validateConfig(config);
const tag = `[${cfg.envPrefix.toLowerCase().replace(/_/g, "-")}]`;

// ── HTTP readiness probe ────────────────────────────────────────────────────
//
// TCP accept readiness is not enough — net.listen() accepts connections before
// route handlers are mounted, so opening the webview during that window results
// in a permanent white screen. We do an actual HTTP GET and require a <500
// response. Two consecutive successes close a small window where the server
// answers once and then blocks (e.g. slow middleware warming up).

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
	// Bun sometimes throws a plain TypeError with no code — narrow on the
	// message so real TypeErrors from buggy code aren't silently swallowed.
	return err.name === "TypeError" && /fetch failed/i.test(err.message);
}

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
		`Server did not become ready at ${baseUrl} within ${timeoutMs}ms`,
	);
}

// ── Mode dispatch ───────────────────────────────────────────────────────────

let targetUrl: string;
let childProc: Subprocess | null = null;

if (cfg.mode === "url") {
	// URL mode: connect to an external service
	targetUrl = process.env[cfg.url.envVar] ?? cfg.url.default;
} else {
	// Command mode: spawn a child process and connect to its HTTP server
	const { command } = cfg;
	const bin = process.env[command.binEnvVar];
	if (!bin) {
		console.error(
			`${tag} ${command.binEnvVar} is not set — did the binary wrapper fail?`,
		);
		process.exit(2);
	}

	const host = process.env[command.hostEnvVar] ?? command.hostDefault;
	const portRaw = process.env[command.portEnvVar] ?? String(command.portDefault);
	const port = Number(portRaw);
	if (!Number.isInteger(port) || port < 1 || port > 65535) {
		console.error(
			`${tag} ${command.portEnvVar} must be an integer in [1,65535], got: ${portRaw}`,
		);
		process.exit(2);
	}

	// Default CWD to $HOME so the child doesn't inherit Electrobun's
	// app-bundle bin/ directory (which would create phantom projects).
	const cwd = process.env[command.cwdEnvVar] ?? process.env["HOME"];
	const pdeathExec = process.env[command.pdeathExecEnvVar];

	// Substitute {port} and {host} placeholders in args
	const args = command.args.map((a) =>
		a === "{port}" ? String(port) : a === "{host}" ? host : a,
	);

	const baseCmd = [bin, ...args];
	childProc = spawn({
		cmd: pdeathExec ? [pdeathExec, ...baseCmd] : baseCmd,
		cwd,
		stdout: "inherit",
		stderr: "inherit",
	});

	targetUrl = `http://${host}:${port}`;
}

// ── Readiness + window ──────────────────────────────────────────────────────

type ReadyResult = { kind: "ready" } | { kind: "exited"; code: number | null };

try {
	if (childProc) {
		// Race HTTP readiness against the child exiting — if the child crashes
		// at startup we'd otherwise poll for the full timeout.
		const result: ReadyResult = await Promise.race([
			waitForHttp(targetUrl, cfg.readinessTimeoutMs).then(() => ({
				kind: "ready" as const,
			})),
			childProc.exited.then((code) => ({
				kind: "exited" as const,
				code,
			})),
		]);
		if (result.kind === "exited") {
			console.error(
				`${tag} child process exited before becoming ready (code ${result.code})`,
			);
			process.exit(1);
		}
	} else {
		await waitForHttp(targetUrl, cfg.readinessTimeoutMs);
	}
} catch (err) {
	console.error(tag, err);
	try {
		childProc?.kill();
	} catch {
		/* already exited */
	}
	process.exit(1);
}

// Belt-and-suspenders cleanup for the rare case where JS is still running on
// shutdown. The usual kill path is pdeath-exec at the kernel level.
if (childProc) {
	const proc = childProc;
	const cleanup = () => {
		try {
			proc.kill();
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
}

new BrowserWindow({
	title: cfg.title,
	url: targetUrl,
	frame: {
		x: 100,
		y: 100,
		width: cfg.window.width,
		height: cfg.window.height,
	},
});

console.log(`${tag} opened window at ${targetUrl}`);

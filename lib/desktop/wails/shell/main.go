// Generic Wails shell for mkWailsApp-generated applications.
//
// Reads config.json (embedded at Nix build time) to determine:
//   mode "url"     — open a window at an external URL
//   mode "command" — spawn a child process, wait for readiness, open window
//
// See lib/desktop/wails/ in mix.nix for the Nix-side builder.
//
// CLAUDE: config.json is generated at Nix build time — do not create manually

package main

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/linux"
	wailsrt "github.com/wailsapp/wails/v2/pkg/runtime"
)

//go:embed frontend
var assets embed.FS

//go:embed config.json
var configBytes []byte

// ── Config types (matching Nix-generated JSON) ─────────────────────────────

type WindowConfig struct {
	Width  int `json:"width"`
	Height int `json:"height"`
}

type URLSpec struct {
	Default string `json:"default"`
	EnvVar  string `json:"envVar"`
}

type CommandSpec struct {
	BinEnvVar   string   `json:"binEnvVar"`
	Args        []string `json:"args"`
	PortDefault int      `json:"portDefault"`
	PortEnvVar  string   `json:"portEnvVar"`
	HostDefault string   `json:"hostDefault"`
	HostEnvVar  string   `json:"hostEnvVar"`
	CWDEnvVar   string   `json:"cwdEnvVar"`
}

type AppConfig struct {
	Mode               string       `json:"mode"`
	Title              string       `json:"title"`
	ProgramName        string       `json:"programName"`
	ReadinessTimeoutMs int          `json:"readinessTimeoutMs"`
	Window             WindowConfig `json:"window"`
	EnvPrefix          string       `json:"envPrefix"`
	URL                *URLSpec     `json:"url,omitempty"`
	Command            *CommandSpec `json:"command,omitempty"`
}

func loadConfig() AppConfig {
	var cfg AppConfig
	if err := json.Unmarshal(configBytes, &cfg); err != nil {
		fmt.Fprintf(os.Stderr, "failed to parse config.json: %v\n", err)
		os.Exit(2)
	}
	if cfg.Mode != "url" && cfg.Mode != "command" {
		fmt.Fprintf(os.Stderr, "invalid config: mode must be \"url\" or \"command\", got %q\n", cfg.Mode)
		os.Exit(2)
	}
	if cfg.Mode == "url" && (cfg.URL == nil || cfg.URL.Default == "") {
		fmt.Fprintf(os.Stderr, "invalid config: url mode requires url.default\n")
		os.Exit(2)
	}
	if cfg.Mode == "command" && (cfg.Command == nil || cfg.Command.BinEnvVar == "") {
		fmt.Fprintf(os.Stderr, "invalid config: command mode requires command.binEnvVar\n")
		os.Exit(2)
	}
	return cfg
}

// ── HTTP readiness probe ────────────────────────────────────────────────────
//
// Polls the target URL until it responds with status < 500.
// Requires 2 consecutive successes to handle middleware warming.

func waitForHTTP(ctx context.Context, baseURL string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	consecutiveOK := 0
	const required = 2

	client := &http.Client{
		Timeout: time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	defer client.CloseIdleConnections()

	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		resp, err := client.Get(baseURL)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode < 500 {
				consecutiveOK++
				if consecutiveOK >= required {
					return nil
				}
				continue
			}
			consecutiveOK = 0
		} else {
			consecutiveOK = 0
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("server did not become ready at %s within %v", baseURL, timeout)
}

// ── Main ────────────────────────────────────────────────────────────────────

func main() {
	cfg := loadConfig()
	tag := fmt.Sprintf("[%s]", strings.ToLower(strings.ReplaceAll(cfg.EnvPrefix, "_", "-")))

	var targetURL string
	var childCmd *exec.Cmd
	childExited := make(chan struct{})

	switch cfg.Mode {
	case "url":
		if v := os.Getenv(cfg.URL.EnvVar); v != "" {
			targetURL = v
		} else {
			targetURL = cfg.URL.Default
		}
		close(childExited) // no child — mark as "done"

	case "command":
		spec := cfg.Command
		bin := os.Getenv(spec.BinEnvVar)
		if bin == "" {
			fmt.Fprintf(os.Stderr, "%s %s is not set — did the binary wrapper fail?\n", tag, spec.BinEnvVar)
			os.Exit(2)
		}

		host := spec.HostDefault
		if v := os.Getenv(spec.HostEnvVar); v != "" {
			host = v
		}

		port := spec.PortDefault
		if v := os.Getenv(spec.PortEnvVar); v != "" {
			p, err := strconv.Atoi(v)
			if err != nil || p < 1 || p > 65535 {
				fmt.Fprintf(os.Stderr, "%s %s must be an integer in [1,65535], got: %s\n", tag, spec.PortEnvVar, v)
				os.Exit(2)
			}
			port = p
		}

		cwd := os.Getenv(spec.CWDEnvVar)
		if cwd == "" {
			cwd = os.Getenv("HOME")
		}

		// Substitute {port} and {host} placeholders
		args := make([]string, len(spec.Args))
		for i, a := range spec.Args {
			switch a {
			case "{port}":
				args[i] = strconv.Itoa(port)
			case "{host}":
				args[i] = host
			default:
				args[i] = a
			}
		}

		childCmd = exec.Command(bin, args...)
		childCmd.Dir = cwd
		childCmd.Stdout = os.Stdout
		childCmd.Stderr = os.Stderr
		childCmd.SysProcAttr = &syscall.SysProcAttr{
			Pdeathsig: syscall.SIGTERM, // kernel-level cleanup — child dies when parent does
		}

		if err := childCmd.Start(); err != nil {
			fmt.Fprintf(os.Stderr, "%s failed to start child process: %v\n", tag, err)
			os.Exit(1)
		}

		// Reap child in background — closing childExited signals it's done
		go func() {
			if err := childCmd.Wait(); err != nil {
				fmt.Fprintf(os.Stderr, "%s child exited: %v\n", tag, err)
			}
			close(childExited)
		}()

		targetURL = fmt.Sprintf("http://%s:%d", host, port)

		// Race HTTP readiness against child exit
		probeCtx, probeCancel := context.WithCancel(context.Background())
		readyCh := make(chan error, 1)
		go func() {
			readyCh <- waitForHTTP(probeCtx, targetURL, time.Duration(cfg.ReadinessTimeoutMs)*time.Millisecond)
		}()

		select {
		case err := <-readyCh:
			probeCancel()
			if err != nil {
				fmt.Fprintf(os.Stderr, "%s %v\n", tag, err)
				killChild(childCmd, childExited)
				os.Exit(1)
			}
		case <-childExited:
			probeCancel()
			fmt.Fprintf(os.Stderr, "%s child process exited before becoming ready\n", tag)
			os.Exit(1)
		}

		// Forward termination signals to child
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
		go func() {
			<-sigCh
			killChild(childCmd, childExited)
		}()
	}

	// ── Wails app ──────────────────────────────────────────────────────────

	fmt.Printf("%s starting — target %s\n", tag, targetURL)

	// OnDomReady fires on every navigation — only redirect once.
	var once sync.Once

	err := wails.Run(&options.App{
		Title:  cfg.Title,
		Width:  cfg.Window.Width,
		Height: cfg.Window.Height,
		// Wails #2431: SetMinMaxSize in window.c defaults MaxWidth/MaxHeight=0
		// to the monitor resolution, then subtracts Wayland decorator offsets
		// that can be negative when measured before the window is mapped.
		// Setting an explicit large max bypasses the monitor-size fallback
		// entirely — GTK won't constrain beyond actual screen bounds anyway.
		MaxWidth:         10000,
		MaxHeight:        10000,
		BackgroundColour: &options.RGBA{R: 30, G: 30, B: 46, A: 255}, // #1e1e2e
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		OnDomReady: func(ctx context.Context) {
			once.Do(func() {
				safeURL, _ := json.Marshal(targetURL)
				wailsrt.WindowExecJS(ctx,
					fmt.Sprintf("window.location.replace(%s)", safeURL))
				fmt.Printf("%s opened window at %s\n", tag, targetURL)
			})
		},
		OnShutdown: func(ctx context.Context) {
			killChild(childCmd, childExited)
		},
		Linux: &linux.Options{
			ProgramName: cfg.ProgramName,
		},
	})

	if err != nil {
		fmt.Fprintf(os.Stderr, "%s wails error: %v\n", tag, err)
		killChild(childCmd, childExited)
		os.Exit(1)
	}
}

// killChild sends SIGTERM, waits briefly, then SIGKILL.
// Safe to call if child is nil or already exited.
func killChild(cmd *exec.Cmd, exited <-chan struct{}) {
	if cmd == nil || cmd.Process == nil {
		return
	}
	select {
	case <-exited:
		return // already done
	default:
	}

	cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-exited:
	case <-time.After(3 * time.Second):
		cmd.Process.Kill()
		<-exited
	}
}

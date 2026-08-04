// Package remote manages TeamViewer-like desktop access via an embedded RustDesk helper.
// The helper ships inside LunaAgent.app — users do not install a separate app.
package remote

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// Status is reported on heartbeat (no secrets).
type Status struct {
	Enabled    bool   `json:"enabled"`
	RustDeskID string `json:"rustdesk_id,omitempty"`
	RelayOK    bool   `json:"relay_ok"`
	Error      string `json:"error,omitempty"`
}

type Config struct {
	IDServer    string
	RelayServer string
	Key         string
	Password    string
}

var (
	mu     sync.Mutex
	active Status
)

func Current() Status {
	mu.Lock()
	defer mu.Unlock()
	return active
}

func setStatus(s Status) {
	mu.Lock()
	active = s
	mu.Unlock()
}

// Enable writes org relay config, sets permanent password on a live --server,
// then opens one GUI. The --server process is kept running — killing it before
// the password flush caused “incorrect password” while panel still saw ack ok.
func Enable(cfg Config) (Status, error) {
	cfg.IDServer = strings.TrimSpace(cfg.IDServer)
	cfg.Key = strings.TrimSpace(cfg.Key)
	cfg.Password = strings.TrimSpace(cfg.Password)
	cfg.RelayServer = strings.TrimSpace(cfg.RelayServer)
	if cfg.IDServer == "" || cfg.Key == "" || cfg.Password == "" {
		st := Status{Enabled: false, Error: "missing_relay_config"}
		setStatus(st)
		return st, fmt.Errorf("id_server, key, and password required")
	}
	idHost := strings.Split(cfg.IDServer, ":")[0]
	if cfg.RelayServer == "" {
		cfg.RelayServer = idHost + ":21117"
	}
	relayHost := strings.Split(cfg.RelayServer, ":")[0]

	app, bin, err := findHelper()
	if err != nil {
		st := Status{Enabled: false, Error: "helper_missing"}
		setStatus(st)
		return st, err
	}

	stopHelper()
	time.Sleep(500 * time.Millisecond)

	if err := writeConfig(cfg); err != nil {
		st := Status{Enabled: false, Error: "config_failed"}
		setStatus(st)
		return st, err
	}

	server := exec.Command(bin, "--server")
	server.Stdout = nil
	server.Stderr = nil
	if err := server.Start(); err != nil {
		st := Status{Enabled: false, Error: "start_failed"}
		setStatus(st)
		return st, err
	}

	time.Sleep(2 * time.Second)
	_ = runQuiet(bin, 10*time.Second, "--set-custom-rendezvous-server", idHost)
	_ = runQuiet(bin, 10*time.Second, "--set-key", cfg.Key)
	_ = runQuiet(bin, 10*time.Second, "--set-relay-server", relayHost)
	_ = runQuiet(bin, 10*time.Second, "--set-verification-method", "use-both-passwords")
	_ = runQuiet(bin, 10*time.Second, "--set-approve-mode", "password")

	pwErr := runQuiet(bin, 25*time.Second, "--password", cfg.Password)
	// Give RustDesk time to flush encrypted password to disk before any further steps.
	time.Sleep(2 * time.Second)
	if pwErr == nil {
		// Second apply — some macOS builds no-op the first call.
		pwErr = runQuiet(bin, 25*time.Second, "--password", cfg.Password)
		time.Sleep(1 * time.Second)
	}

	id := strings.TrimSpace(getID(bin))

	_ = writeConfig(cfg)
	if err := ensureRunning(app, bin); err != nil {
		_ = server.Process.Kill()
		st := Status{Enabled: false, Error: "start_failed", RustDeskID: id}
		setStatus(st)
		return st, err
	}

	// Keep --server alive (do not kill). Reap in background when it exits.
	go func() {
		_ = server.Wait()
	}()

	if id == "" {
		time.Sleep(2 * time.Second)
		id = strings.TrimSpace(getID(bin))
	}

	st := Status{
		Enabled:    true,
		RustDeskID: id,
		// Only claim relay when we have an ID; true online check is hbbs-side.
		RelayOK: id != "",
	}
	if id == "" {
		st.Error = "id_pending"
	}
	setStatus(st)
	if pwErr != nil {
		st.Error = "password_apply_failed"
		setStatus(st)
		return st, fmt.Errorf("failed to set permanent password: %w", pwErr)
	}
	return st, nil
}

func Disable() Status {
	_, bin, _ := findHelper()
	if bin != "" {
		_ = runQuiet(bin, 8*time.Second, "--password", "")
	}
	stopHelper()
	_ = wipeConfigSecrets()
	st := Status{Enabled: false}
	setStatus(st)
	return st
}

func stopHelper() {
	_ = exec.Command("pkill", "-f", "Resources/RustDesk-").Run()
	_ = exec.Command("pkill", "-f", "RustDesk.app/Contents/MacOS").Run()
	time.Sleep(400 * time.Millisecond)
}

func runQuiet(bin string, timeout time.Duration, args ...string) error {
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("timeout: rustdesk %s", strings.Join(args, " "))
	}
	return err
}

func rustdeskArchFolder() string {
	if runtime.GOARCH == "amd64" {
		return "x86_64"
	}
	return "aarch64"
}

func resourcesDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Clean(filepath.Join(filepath.Dir(exe), "..", "Resources"))
}

func findHelper() (appPath, binPath string, err error) {
	if p := strings.TrimSpace(os.Getenv("LUNA_RUSTDESK_BIN")); p != "" {
		if st, e := os.Stat(p); e == nil && !st.IsDir() {
			return "", p, nil
		}
	}
	res := resourcesDir()
	if res != "" {
		arch := rustdeskArchFolder()
		for _, name := range []string{
			filepath.Join(res, "RustDesk-"+arch+".app"),
			filepath.Join(res, "RustDesk.app"),
		} {
			for _, mac := range []string{
				filepath.Join(name, "Contents/MacOS/RustDesk"),
				filepath.Join(name, "Contents/MacOS/rustdesk"),
			} {
				if st, e := os.Stat(mac); e == nil && !st.IsDir() {
					return name, mac, nil
				}
			}
		}
	}
	return "", "", fmt.Errorf("remote helper missing inside LunaAgent — reinstall the agent package")
}

func configPaths() []string {
	var out []string
	if u, err := user.Current(); err == nil && u.HomeDir != "" {
		out = append(out, filepath.Join(u.HomeDir, "Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"))
	}
	if support, err := os.UserConfigDir(); err == nil {
		out = append(out, filepath.Join(support, "LunaAgent", "rustdesk", "RustDesk2.toml"))
	}
	return out
}

func writeConfig(cfg Config) error {
	idHost := cfg.IDServer
	rendezvous := idHost
	if !strings.Contains(idHost, ":") {
		rendezvous = idHost + ":21116"
	}
	idOnly := strings.Split(idHost, ":")[0]
	relay := cfg.RelayServer
	if relay == "" {
		relay = idOnly + ":21117"
	}
	body := fmt.Sprintf(`rendezvous_server = '%s'
nat_type = 1
serial = 0

[options]
custom-rendezvous-server = '%s'
relay-server = '%s'
key = '%s'
verification-method = 'use-both-passwords'
approve-mode = 'password'
allow-remote-config-modification = 'N'
`, rendezvous, idOnly, relay, cfg.Key)

	wrote := false
	for _, path := range configPaths() {
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			continue
		}
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			return err
		}
		wrote = true
	}
	if !wrote {
		return fmt.Errorf("could not write remote helper config")
	}
	return nil
}

func wipeConfigSecrets() error {
	for _, path := range configPaths() {
		_ = os.Remove(path)
	}
	return nil
}

func ensureRunning(app, bin string) error {
	if app != "" {
		if err := exec.Command("open", "-a", app).Run(); err == nil {
			return nil
		}
		if err := exec.Command("open", app).Run(); err == nil {
			return nil
		}
	}
	cmd := exec.Command(bin)
	return cmd.Start()
}

func getID(bin string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, "--get-id")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return ""
	}
	line := strings.TrimSpace(string(out))
	parts := strings.Split(line, "\n")
	for i := len(parts) - 1; i >= 0; i-- {
		p := strings.TrimSpace(parts[i])
		if p != "" && !strings.Contains(strings.ToLower(p), "error") {
			return p
		}
	}
	return line
}

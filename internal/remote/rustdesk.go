// Package remote manages TeamViewer-like desktop access via an embedded RustDesk helper.
// The helper ships inside LunaAgent.app — users do not install a separate app.
package remote

import (
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
	IDServer    string // host or host:port for hbbs (default port 21116)
	RelayServer string // host:21117
	Key         string // id_ed25519.pub contents
	Password    string // permanent session password
}

var (
	mu     sync.Mutex
	active Status
)

// Current returns the last known session status (safe for heartbeat).
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

// Enable configures the embedded remote helper for the org relay and starts it.
//
// macOS password apply requires a short-lived `--server` process (official
// RustDesk deploy script). Permanent password alone fails if verification
// method is temporary-only — we force use-both-passwords.
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

	app, bin, err := findHelper()
	if err != nil {
		st := Status{Enabled: false, Error: "helper_missing"}
		setStatus(st)
		return st, err
	}

	stopHelper()

	if err := writeConfig(cfg); err != nil {
		st := Status{Enabled: false, Error: "config_failed"}
		setStatus(st)
		return st, err
	}

	// Official macOS deploy order: --server → --password → (config already written).
	server := exec.Command(bin, "--server")
	server.Stdout = nil
	server.Stderr = nil
	_ = server.Start()
	time.Sleep(1200 * time.Millisecond)

	_ = runQuiet(bin, "--password", cfg.Password)
	time.Sleep(400 * time.Millisecond)
	_ = runQuiet(bin, "--set-verification-method", "use-both-passwords")
	_ = runQuiet(bin, "--set-approve-mode", "password")
	_ = runQuiet(bin, "--set-custom-rendezvous-server", idHost)
	_ = runQuiet(bin, "--set-key", cfg.Key)
	_ = runQuiet(bin, "--set-relay-server", cfg.RelayServer)
	// Re-apply password after options (some builds reset it).
	_ = runQuiet(bin, "--password", cfg.Password)

	id := strings.TrimSpace(getID(bin))

	// Kill headless server, then open GUI for Screen Recording prompts.
	if server.Process != nil {
		_ = server.Process.Kill()
	}
	stopHelper()
	time.Sleep(300 * time.Millisecond)

	// Re-write config in case GUI/server rewrote defaults while we ran.
	_ = writeConfig(cfg)

	if err := ensureRunning(app, bin); err != nil {
		st := Status{Enabled: false, Error: "start_failed", RustDeskID: id}
		setStatus(st)
		return st, err
	}

	time.Sleep(1500 * time.Millisecond)
	// Final password set against the live GUI/service.
	_ = runQuiet(bin, "--password", cfg.Password)
	if id == "" {
		id = strings.TrimSpace(getID(bin))
	}

	st := Status{
		Enabled:    true,
		RustDeskID: id,
		RelayOK:    id != "",
	}
	if id == "" {
		st.Error = "id_pending"
	}
	setStatus(st)
	return st, nil
}

// Disable stops accepting remote control (clears password / stops helper best-effort).
func Disable() Status {
	_, bin, _ := findHelper()
	if bin != "" {
		_ = runQuiet(bin, "--password", "")
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

func runQuiet(bin string, args ...string) error {
	cmd := exec.Command(bin, args...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
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

// findHelper prefers the RustDesk.app embedded in LunaAgent.app/Contents/Resources.
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
		// Options / network live in RustDesk2.toml on macOS.
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
	// use-both-passwords: macOS often ignores --password unless both are allowed.
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
`, rendezvous, idOnly, cfg.RelayServer, cfg.Key)

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
		if err := exec.Command("open", "-n", "-a", app).Run(); err == nil {
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
	out, err := exec.Command(bin, "--get-id").CombinedOutput()
	if err != nil {
		return ""
	}
	line := strings.TrimSpace(string(out))
	// Prefer last non-empty line (GUI noise sometimes precedes the id).
	parts := strings.Split(line, "\n")
	for i := len(parts) - 1; i >= 0; i-- {
		p := strings.TrimSpace(parts[i])
		if p != "" && !strings.Contains(strings.ToLower(p), "error") {
			return p
		}
	}
	return line
}

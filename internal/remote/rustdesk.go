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
// Important on macOS: do not set options on a short-lived --server then kill it —
// the GUI often boots back onto the public network. Write toml, open GUI, then
// apply --set-* / --password against the live process and wait for an ID.
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

	if err := ensureRunning(app, bin); err != nil {
		st := Status{Enabled: false, Error: "start_failed"}
		setStatus(st)
		return st, err
	}

	// Give the GUI time to read toml, then force org relay (CLI sticks better live).
	time.Sleep(2 * time.Second)
	applyRelayCLI(bin, idHost, relayHost, cfg.RelayServer, cfg.Key, cfg.Password)
	// GUI sometimes rewrites options on first paint — pin again.
	time.Sleep(1500 * time.Millisecond)
	_ = writeConfig(cfg)
	applyRelayCLI(bin, idHost, relayHost, cfg.RelayServer, cfg.Key, cfg.Password)

	id := ""
	for i := 0; i < 8; i++ {
		time.Sleep(500 * time.Millisecond)
		id = strings.TrimSpace(getID(bin))
		if id != "" {
			break
		}
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

func applyRelayCLI(bin, idHost, relayHost, relayServer, key, password string) {
	_ = runQuiet(bin, "--set-custom-rendezvous-server", idHost)
	_ = runQuiet(bin, "--set-key", key)
	// Some builds want host only; others accept host:port — set both shapes.
	_ = runQuiet(bin, "--set-relay-server", relayHost)
	if relayServer != "" && relayServer != relayHost {
		_ = runQuiet(bin, "--set-relay-server", relayServer)
	}
	_ = runQuiet(bin, "--set-verification-method", "use-both-passwords")
	_ = runQuiet(bin, "--set-approve-mode", "password")
	_ = runQuiet(bin, "--password", password)
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
		base := filepath.Join(u.HomeDir, "Library/Preferences/com.carriez.RustDesk")
		out = append(out,
			filepath.Join(base, "RustDesk2.toml"),
			filepath.Join(base, "RustDesk.toml"),
		)
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
	body2 := fmt.Sprintf(`rendezvous_server = '%s'
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
		content := body2
		// RustDesk.toml holds identity; only touch options file content for *2.toml.
		if strings.HasSuffix(path, "RustDesk.toml") && !strings.HasSuffix(path, "RustDesk2.toml") {
			// Do not wipe encrypted id/password store — leave file if present.
			if _, err := os.Stat(path); err == nil {
				continue
			}
			content = ""
		}
		if content == "" {
			continue
		}
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
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
		if strings.HasSuffix(path, "RustDesk2.toml") {
			_ = os.Remove(path)
		}
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
	parts := strings.Split(line, "\n")
	for i := len(parts) - 1; i >= 0; i-- {
		p := strings.TrimSpace(parts[i])
		if p != "" && !strings.Contains(strings.ToLower(p), "error") {
			return p
		}
	}
	return line
}

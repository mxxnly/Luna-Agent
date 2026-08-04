// Package remote manages TeamViewer-like desktop access via an embedded RustDesk helper.
// The helper ships inside LunaAgent.app — users do not install a separate app.
package remote

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
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

var (
	rePasswordLine = regexp.MustCompile(`(?m)^password\s*=\s*(?:'[^']*'|"[^"]*"|\S+)\s*$`)
	reSaltLine     = regexp.MustCompile(`(?m)^salt\s*=\s*(?:'[^']*'|"[^"]*"|\S+)\s*$`)
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

// Enable writes org relay config + permanent password into RustDesk.toml, then
// starts --server and one GUI.
//
// Important: RustDesk's `--password` CLI only works when the binary lives in
// /Applications/RustDesk.app AND runs as root. Our helper is embedded under
// LunaAgent.app and runs as the user LaunchAgent, so CLI always prints
// "Installation and administrative privileges required!" with exit 0 — panel
// saw ok while password stayed empty. We write password into RustDesk.toml
// instead; RustDesk hashes/encrypts it on next load.
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
	if err := writePermanentPassword(cfg.Password); err != nil {
		st := Status{Enabled: false, Error: "password_apply_failed"}
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

	id := strings.TrimSpace(getID(bin))

	_ = writeConfig(cfg)
	if err := ensureRunning(app, bin); err != nil {
		_ = server.Process.Kill()
		st := Status{Enabled: false, Error: "start_failed", RustDeskID: id}
		setStatus(st)
		return st, err
	}

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
		RelayOK:    id != "",
	}
	if id == "" {
		st.Error = "id_pending"
	}
	setStatus(st)
	return st, nil
}

func Disable() Status {
	stopHelper()
	_ = writePermanentPassword("")
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

func identityTomlPaths() []string {
	var out []string
	if u, err := user.Current(); err == nil && u.HomeDir != "" {
		out = append(out, filepath.Join(u.HomeDir, "Library/Preferences/com.carriez.RustDesk/RustDesk.toml"))
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

// writePermanentPassword sets password= in RustDesk.toml (plaintext; hashed on load).
// Panel passwords are alphanumeric; single-quote TOML is safe.
func writePermanentPassword(password string) error {
	paths := identityTomlPaths()
	if len(paths) == 0 {
		return fmt.Errorf("no identity toml path")
	}
	wrote := false
	for _, path := range paths {
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			continue
		}
		body, err := os.ReadFile(path)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		next, err := patchIdentityPassword(string(body), password)
		if err != nil {
			return err
		}
		if err := os.WriteFile(path, []byte(next), 0o600); err != nil {
			return err
		}
		wrote = true
	}
	if !wrote {
		return fmt.Errorf("could not write permanent password")
	}
	return nil
}

func patchIdentityPassword(body, password string) (string, error) {
	if strings.ContainsAny(password, "'\"\n\r") {
		return "", fmt.Errorf("password contains unsupported characters")
	}
	line := fmt.Sprintf("password = '%s'", password)
	if strings.TrimSpace(body) == "" {
		salt, err := randomSalt(32)
		if err != nil {
			return "", err
		}
		return line + "\nsalt = '" + salt + "'\n", nil
	}
	if rePasswordLine.MatchString(body) {
		body = rePasswordLine.ReplaceAllString(body, line)
	} else {
		body = line + "\n" + body
	}
	if !reSaltLine.MatchString(body) {
		salt, err := randomSalt(32)
		if err != nil {
			return "", err
		}
		body = "salt = '" + salt + "'\n" + body
	}
	return body, nil
}

func randomSalt(n int) (string, error) {
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	out := make([]byte, n)
	max := big.NewInt(int64(len(alphabet)))
	for i := 0; i < n; i++ {
		v, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		out[i] = alphabet[v.Int64()]
	}
	return string(out), nil
}

func wipeConfigSecrets() error {
	for _, path := range configPaths() {
		_ = os.Remove(path)
	}
	_ = writePermanentPassword("")
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

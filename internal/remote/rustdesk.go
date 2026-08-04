// Package remote manages TeamViewer-like desktop access via an embedded RustDesk helper.
// The helper ships inside LunaAgent.app — users do not install a separate app from the internet.
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

const userHelperAppName = "LunaRemote.app"

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

// Enable installs the helper at a stable user path, writes relay + password, then
// launches ONE GUI (no separate --server). Nested Resources/RustDesk-*.app loses
// Screen Recording across kill/relaunch even while System Settings still shows
// the toggle on — ~/Applications/LunaRemote.app keeps TCC across Remote off/on.
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
	if cfg.RelayServer == "" {
		cfg.RelayServer = strings.Split(cfg.IDServer, ":")[0] + ":21117"
	}

	firstInstall := false
	app, bin, err := ensureUserHelper(&firstInstall)
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

	if err := ensureRunning(app, bin); err != nil {
		st := Status{Enabled: false, Error: "start_failed"}
		setStatus(st)
		return st, err
	}

	time.Sleep(2 * time.Second)
	id := strings.TrimSpace(getID(bin))
	if id == "" {
		time.Sleep(2 * time.Second)
		id = strings.TrimSpace(getID(bin))
	}

	if firstInstall {
		openScreenPrivacy()
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
	// Clear secrets first, then quit so in-memory password cannot linger.
	_ = writePermanentPassword("")
	_ = wipeConfigSecrets()
	stopHelper()
	st := Status{Enabled: false}
	setStatus(st)
	return st
}

func stopHelper() {
	_ = exec.Command("pkill", "-f", "LunaRemote.app/Contents/MacOS").Run()
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

func userHelperAppPath() (string, error) {
	u, err := user.Current()
	if err != nil || u.HomeDir == "" {
		return "", fmt.Errorf("no home directory")
	}
	return filepath.Join(u.HomeDir, "Applications", userHelperAppName), nil
}

func embeddedHelperApp() (string, error) {
	res := resourcesDir()
	if res == "" {
		return "", fmt.Errorf("resources dir missing")
	}
	arch := rustdeskArchFolder()
	for _, name := range []string{
		filepath.Join(res, "RustDesk-"+arch+".app"),
		filepath.Join(res, "RustDesk.app"),
	} {
		bin := filepath.Join(name, "Contents/MacOS/RustDesk")
		if st, e := os.Stat(bin); e == nil && !st.IsDir() {
			return name, nil
		}
		bin = filepath.Join(name, "Contents/MacOS/rustdesk")
		if st, e := os.Stat(bin); e == nil && !st.IsDir() {
			return name, nil
		}
	}
	return "", fmt.Errorf("remote helper missing inside LunaAgent — reinstall the agent package")
}

func helperBinary(app string) string {
	for _, name := range []string{
		filepath.Join(app, "Contents/MacOS/RustDesk"),
		filepath.Join(app, "Contents/MacOS/rustdesk"),
	} {
		if st, e := os.Stat(name); e == nil && !st.IsDir() {
			return name
		}
	}
	return ""
}

// ensureUserHelper copies the embedded helper to ~/Applications/LunaRemote.app
// so Screen Recording TCC survives Remote off/on (nested Resources path does not).
func ensureUserHelper(firstInstall *bool) (appPath, binPath string, err error) {
	if p := strings.TrimSpace(os.Getenv("LUNA_RUSTDESK_BIN")); p != "" {
		if st, e := os.Stat(p); e == nil && !st.IsDir() {
			return "", p, nil
		}
	}
	src, err := embeddedHelperApp()
	if err != nil {
		return "", "", err
	}
	dst, err := userHelperAppPath()
	if err != nil {
		return "", "", err
	}

	srcBin := helperBinary(src)
	dstBin := helperBinary(dst)
	needCopy := dstBin == ""
	if !needCopy {
		ss, se := os.Stat(srcBin)
		ds, de := os.Stat(dstBin)
		if se != nil || de != nil || ss.Size() != ds.Size() || ss.ModTime().After(ds.ModTime()) {
			needCopy = true
		}
	} else if firstInstall != nil {
		*firstInstall = true
	}

	if needCopy {
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return "", "", err
		}
		_ = os.RemoveAll(dst)
		cmd := exec.Command("ditto", src, dst)
		if out, e := cmd.CombinedOutput(); e != nil {
			return "", "", fmt.Errorf("install LunaRemote: %w (%s)", e, strings.TrimSpace(string(out)))
		}
		if firstInstall != nil && dstBin == "" {
			*firstInstall = true
		}
	}

	bin := helperBinary(dst)
	if bin == "" {
		return "", "", fmt.Errorf("LunaRemote binary missing after install")
	}
	return dst, bin, nil
}

func findHelper() (appPath, binPath string, err error) {
	var first bool
	return ensureUserHelper(&first)
}

// openScreenPrivacy opens macOS Screen Recording settings (first install only).
func openScreenPrivacy() {
	urls := []string{
		"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
		"x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_ScreenCapture",
	}
	for _, u := range urls {
		if exec.Command("open", u).Run() == nil {
			return
		}
	}
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
		// Prefer path open (stable TCC identity) over -a by name.
		if err := exec.Command("open", app).Run(); err == nil {
			return nil
		}
		if err := exec.Command("open", "-a", app).Run(); err == nil {
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

package wg

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

var (
	ErrInvalidConf = errors.New("invalid wireguard config")
	ErrNotUp       = errors.New("tunnel not up")
)

// Manager applies WireGuard configs with backup/rollback.
// When DryRun is true (CI), no TUN is opened; state is tracked in memory/files only.
type Manager struct {
	Dir    string
	DryRun bool

	mu     sync.Mutex
	up     bool
	lastIP string
}

func (m *Manager) confPath() string   { return filepath.Join(m.Dir, "wg0.conf") }
func (m *Manager) backupPath() string { return filepath.Join(m.Dir, "wg0.conf.prev") }
func (m *Manager) statePath() string  { return filepath.Join(m.Dir, "state") }

// ValidateConf requires [Interface] and [Peer] sections and a PrivateKey line.
func ValidateConf(conf string) error {
	if !strings.Contains(conf, "[Interface]") || !strings.Contains(conf, "[Peer]") {
		return fmt.Errorf("%w: missing Interface/Peer", ErrInvalidConf)
	}
	if !strings.Contains(conf, "PrivateKey") {
		return fmt.Errorf("%w: missing PrivateKey", ErrInvalidConf)
	}
	if !strings.Contains(conf, "Endpoint") {
		return fmt.Errorf("%w: missing Endpoint", ErrInvalidConf)
	}
	if !strings.Contains(conf, "AllowedIPs") {
		return fmt.Errorf("%w: missing AllowedIPs", ErrInvalidConf)
	}
	for _, line := range strings.Split(conf, "\n") {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "#") || trim == "" {
			continue
		}
		if strings.ContainsAny(trim, ";`$|") {
			return fmt.Errorf("%w: forbidden characters", ErrInvalidConf)
		}
	}
	return nil
}

func extractAddress(conf string) string {
	for _, line := range strings.Split(conf, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Address") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				ip := strings.TrimSpace(parts[1])
				if i := strings.Index(ip, "/"); i > 0 {
					return ip[:i]
				}
				return ip
			}
		}
	}
	return ""
}

// Apply writes conf atomically, keeping previous as backup. Does not bring tunnel up.
func (m *Manager) Apply(conf string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := ValidateConf(conf); err != nil {
		return err
	}
	if err := os.MkdirAll(m.Dir, 0o700); err != nil {
		return err
	}
	path := m.confPath()
	if _, err := os.Stat(path); err == nil {
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if err := os.WriteFile(m.backupPath(), data, 0o600); err != nil {
			return err
		}
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(conf), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// Up brings the tunnel up (or dry-run).
func (m *Manager) Up() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, err := os.ReadFile(m.confPath())
	if err != nil {
		return err
	}
	if err := ValidateConf(string(data)); err != nil {
		return err
	}
	if m.DryRun {
		m.up = true
		m.lastIP = extractAddress(string(data))
		_ = os.WriteFile(m.statePath(), []byte("up"), 0o600)
		return nil
	}
	// Idempotent: already up — do not bounce wg-quick.
	if m.tunnelAlive() {
		m.up = true
		if m.lastIP == "" {
			m.lastIP = extractAddress(string(data))
		}
		_ = os.WriteFile(m.statePath(), []byte("up"), 0o600)
		return nil
	}
	if err := m.startTUN(string(data)); err != nil {
		m.up = false
		return err
	}
	m.up = true
	m.lastIP = extractAddress(string(data))
	_ = os.WriteFile(m.statePath(), []byte("up"), 0o600)
	return nil
}

func (m *Manager) rollbackLocked(cause error) error {
	bak := m.backupPath()
	if _, err := os.Stat(bak); err != nil {
		m.up = false
		return cause
	}
	data, err := os.ReadFile(bak)
	if err != nil {
		return errors.Join(cause, err)
	}
	if err := os.WriteFile(m.confPath(), data, 0o600); err != nil {
		return errors.Join(cause, err)
	}
	m.up = false
	_ = os.WriteFile(m.statePath(), []byte("down"), 0o600)
	return fmt.Errorf("%w (rolled back): %v", ErrInvalidConf, cause)
}

// Down stops the tunnel. Returns an error if the interface is still present afterward.
func (m *Manager) Down() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.DryRun {
		m.up = false
		m.lastIP = ""
		_ = os.WriteFile(m.statePath(), []byte("down"), 0o600)
		return nil
	}
	err := m.stopTUN()
	// Always refresh from OS — stop may have partially succeeded.
	alive := m.tunnelAlive()
	if alive {
		m.up = true
		if err != nil {
			return err
		}
		return errors.New("tunnel still up after disconnect")
	}
	m.up = false
	m.lastIP = ""
	_ = os.WriteFile(m.statePath(), []byte("down"), 0o600)
	if err != nil {
		// Interface gone despite helper/osascript noise — treat as success.
		return nil
	}
	return nil
}

// ClearConfigs removes saved WireGuard conf files after unenroll/revoke.
func (m *Manager) ClearConfigs() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.up = false
	m.lastIP = ""
	for _, name := range []string{"wg0.conf", "wg0.conf.prev", "wg0.state"} {
		_ = os.Remove(filepath.Join(m.Dir, name))
	}
	return nil
}

// HasConfig reports whether a WireGuard conf file is present.
func (m *Manager) HasConfig() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, err := os.Stat(m.confPath())
	return err == nil
}

// ReadConfig returns the saved WireGuard conf text, or empty if none.
func (m *Manager) ReadConfig() (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, err := os.ReadFile(m.confPath())
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	return string(data), nil
}

// Mode returns "dry-run" or "live".
func (m *Manager) Mode() string {
	if m.DryRun {
		return "dry-run"
	}
	return "live"
}

// State returns up/down and optional internal IP (refreshes from OS when live).
func (m *Manager) State() (up bool, internalIP string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.DryRun {
		alive := m.tunnelAlive()
		m.up = alive
		if alive {
			if m.lastIP == "" {
				if data, err := os.ReadFile(m.confPath()); err == nil {
					m.lastIP = extractAddress(string(data))
				}
			}
		} else {
			m.lastIP = ""
		}
	}
	return m.up, m.lastIP
}

// ApplyAndUp applies conf then ups; on up failure rolls back to previous conf.
func (m *Manager) ApplyAndUp(conf string) error {
	if err := m.Apply(conf); err != nil {
		return err
	}
	if err := m.Up(); err != nil {
		m.mu.Lock()
		defer m.mu.Unlock()
		return m.rollbackLocked(err)
	}
	return nil
}

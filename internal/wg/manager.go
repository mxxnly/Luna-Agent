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

func (m *Manager) confPath() string     { return filepath.Join(m.Dir, "wg0.conf") }
func (m *Manager) backupPath() string   { return filepath.Join(m.Dir, "wg0.conf.prev") }
func (m *Manager) statePath() string    { return filepath.Join(m.Dir, "state") }

// ValidateConf requires [Interface] and [Peer] sections and a PrivateKey line.
func ValidateConf(conf string) error {
	if !strings.Contains(conf, "[Interface]") || !strings.Contains(conf, "[Peer]") {
		return fmt.Errorf("%w: missing Interface/Peer", ErrInvalidConf)
	}
	if !strings.Contains(conf, "PrivateKey") {
		return fmt.Errorf("%w: missing PrivateKey", ErrInvalidConf)
	}
	// Reject obvious shell injection attempts in Address/Endpoint lines.
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
	if err := os.Rename(tmp, path); err != nil {
		return err
	}
	return nil
}

// Up brings the tunnel up (or dry-run). On failure restores backup if present.
func (m *Manager) Up() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, err := os.ReadFile(m.confPath())
	if err != nil {
		return err
	}
	if err := ValidateConf(string(data)); err != nil {
		return m.rollbackLocked(err)
	}
	if m.DryRun {
		m.up = true
		m.lastIP = extractAddress(string(data))
		_ = os.WriteFile(m.statePath(), []byte("up"), 0o600)
		return nil
	}
	// Real TUN path reserved for privileged helper; treat missing helper as dry failure → rollback.
	if err := m.startTUN(string(data)); err != nil {
		return m.rollbackLocked(err)
	}
	m.up = true
	m.lastIP = extractAddress(string(data))
	_ = os.WriteFile(m.statePath(), []byte("up"), 0o600)
	return nil
}

func (m *Manager) startTUN(_ string) error {
	// Placeholder until privilege helper ships; force callers in production to set DryRun or implement helper.
	return errors.New("tun helper not available; set LUNA_WG_DRY_RUN=1 or install helper")
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

// Down stops the tunnel.
func (m *Manager) Down() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.up = false
	m.lastIP = ""
	_ = os.WriteFile(m.statePath(), []byte("down"), 0o600)
	return nil
}

// State returns up/down and optional internal IP.
func (m *Manager) State() (up bool, internalIP string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.up, m.lastIP
}

// ApplyAndUp applies conf then ups; on up failure rolls back.
func (m *Manager) ApplyAndUp(conf string) error {
	if err := m.Apply(conf); err != nil {
		return err
	}
	return m.Up()
}

package wg

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/bundlepath"
)

func (m *Manager) ifaceName() string {
	base := filepath.Base(m.confPath())
	return strings.TrimSuffix(base, filepath.Ext(base))
}

func (m *Manager) nameFilePath() string {
	return filepath.Join("/var/run/wireguard", m.ifaceName()+".name")
}

func findOnPath(name string) string {
	ordered := bundlepath.ToolCandidates(name)
	if p, err := exec.LookPath(name); err == nil {
		ordered = append(ordered, p)
	}
	ordered = append(ordered, "/usr/bin/"+name)
	for _, p := range ordered {
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	return ""
}

func (m *Manager) startTUN(_ string) error {
	if helperAvailable() {
		if err := callHelper("up"); err != nil {
			return err
		}
		return m.waitAlive()
	}
	// Fallback: one-shot admin password (no helper installed yet).
	return m.startTUNElevated()
}

func (m *Manager) stopTUN() error {
	if helperAvailable() {
		return callHelper("down")
	}
	return m.stopTUNElevated()
}

func (m *Manager) waitAlive() error {
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if m.tunnelAlive() {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	if m.tunnelAlive() {
		return nil
	}
	return errors.New("tunnel helper returned ok but interface not found")
}

func (m *Manager) startTUNElevated() error {
	wgQuick := findOnPath("wg-quick")
	wgGo := findOnPath("wireguard-go")
	bash4 := findBash4()
	if wgQuick == "" {
		return errors.New("wg-quick not found — reinstall LunaAgent.pkg (bundles WireGuard) or: brew install wireguard-tools wireguard-go")
	}
	if bash4 == "" {
		return errors.New("bash 4+ not found — reinstall LunaAgent.pkg or: brew install bash")
	}
	if runtime.GOOS == "darwin" && wgGo == "" {
		return errors.New("wireguard-go not found — reinstall LunaAgent.pkg or: brew install wireguard-go")
	}
	conf := m.confPath()
	pathExport := bundlepath.ToolPATH("")
	shell := fmt.Sprintf(
		`export PATH=%q; export WG_QUICK_USERSPACE_IMPLEMENTATION=%q; %q %q up %q`,
		pathExport, wgGo, bash4, wgQuick, conf,
	)
	if wgGo == "" {
		shell = fmt.Sprintf(
			`export PATH=%q; %q %q up %q`,
			pathExport, bash4, wgQuick, conf,
		)
	}
	if err := runElevated(shell); err != nil {
		return err
	}
	return m.waitAlive()
}

func (m *Manager) stopTUNElevated() error {
	wgQuick := findOnPath("wg-quick")
	bash4 := findBash4()
	if wgQuick == "" {
		return errors.New("wg-quick not found")
	}
	if bash4 == "" {
		return errors.New("bash 4+ not found")
	}
	conf := m.confPath()
	shell := fmt.Sprintf(
		`export PATH=%q; %q %q down %q`,
		bundlepath.ToolPATH(""), bash4, wgQuick, conf,
	)
	return runElevated(shell)
}

func findBash4() string {
	for _, p := range bundlepath.ToolCandidates("bash") {
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			_ = exec.Command("xattr", "-cr", p).Run()
			out, err := exec.Command(p, "-c", "echo ${BASH_VERSINFO[0]}").CombinedOutput()
			if err != nil {
				continue
			}
			v := strings.TrimSpace(string(out))
			if len(v) > 0 && v[0] >= '4' {
				return p
			}
		}
	}
	return ""
}

func (m *Manager) tunnelAlive() bool {
	if st, err := HelperTunnelStatus(); err == nil {
		return st.Up || st.HandshakeOK
	}
	if _, err := os.Stat(m.nameFilePath()); err == nil {
		return true
	}
	wg := findOnPath("wg")
	if wg == "" {
		return false
	}
	out, err := exec.Command(wg, "show", m.ifaceName()).CombinedOutput()
	if err != nil {
		return false
	}
	return len(bytes.TrimSpace(out)) > 0
}

// HasRecentHandshake reports whether the peer has a live handshake / traffic.
// Prefer the root helper — userspace wireguard-go sockets are root-only.
func (m *Manager) HasRecentHandshake() bool {
	if m.DryRun {
		m.mu.Lock()
		defer m.mu.Unlock()
		return m.up
	}
	if st, err := HelperTunnelStatus(); err == nil {
		return st.HandshakeOK
	}
	wg := findOnPath("wg")
	if wg == "" {
		return false
	}
	out, err := exec.Command(wg, "show", m.ifaceName(), "latest-handshakes").CombinedOutput()
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		ts := fields[len(fields)-1]
		if ts != "0" && ts != "" {
			return true
		}
	}
	return false
}

// HelperOK reports whether the root WireGuard helper socket answers ping.
func HelperOK() bool {
	return helperAvailable()
}

func runElevated(shellCmd string) error {
	if os.Getenv("LUNA_WG_NO_ELEVATE") == "1" {
		return errors.New("elevation disabled (test)")
	}
	if runtime.GOOS == "darwin" && os.Geteuid() != 0 {
		return runViaOSASCRIPT(shellCmd)
	}
	cmd := exec.Command("bash", "-lc", shellCmd)
	out, err := cmd.CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("%s", msg)
	}
	return nil
}

func runViaOSASCRIPT(shellCmd string) error {
	escaped := strings.ReplaceAll(shellCmd, `\`, `\\`)
	escaped = strings.ReplaceAll(escaped, `"`, `\"`)
	script := fmt.Sprintf(`do shell script "%s" with administrator privileges`, escaped)
	cmd := exec.Command("osascript", "-e", script)
	out, err := cmd.CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		lower := strings.ToLower(msg)
		if strings.Contains(lower, "user canceled") || strings.Contains(lower, "user cancelled") {
			return errors.New("administrator password canceled")
		}
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("%s", msg)
	}
	return nil
}

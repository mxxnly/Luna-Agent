package wg

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const helperSock = "/var/run/luna-wg.sock"

type helperReq struct {
	Op     string `json:"op"`
	URL    string `json:"url,omitempty"`
	SHA256 string `json:"sha256,omitempty"`
}

type helperRes struct {
	OK          bool   `json:"ok"`
	Error       string `json:"error,omitempty"`
	Up          bool   `json:"up,omitempty"`
	HandshakeOK bool   `json:"handshake_ok,omitempty"`
	Iface       string `json:"iface,omitempty"`
	RxBytes     int64  `json:"rx_bytes,omitempty"`
	TxBytes     int64  `json:"tx_bytes,omitempty"`
}

// TunnelStatus is live WireGuard state from the root helper (authoritative).
type TunnelStatus struct {
	Up          bool
	HandshakeOK bool
	Iface       string
	RxBytes     int64
	TxBytes     int64
}

func helperAvailable() bool {
	if os.Getenv("LUNA_WG_NO_ELEVATE") == "1" {
		return false
	}
	c, err := net.DialTimeout("unix", helperSock, 200*time.Millisecond)
	if err != nil {
		return false
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(500 * time.Millisecond))
	_ = json.NewEncoder(c).Encode(helperReq{Op: "ping"})
	var res helperRes
	if err := json.NewDecoder(c).Decode(&res); err != nil {
		return false
	}
	return res.OK
}

func callHelper(op string) error {
	_, err := callHelperRaw(helperReq{Op: op})
	return err
}

// InstallPkg downloads, verifies, and installs a .pkg.
// Prefers the root helper; if it is offline, installs the helper once (Mac password)
// then retries; last resort is a one-shot elevated installer.
func InstallPkg(url, sha256 string) error {
	url = strings.TrimSpace(url)
	sha256 = strings.ToLower(strings.TrimSpace(sha256))
	if url == "" || sha256 == "" {
		return fmt.Errorf("url and sha256 required")
	}

	_ = EnsureRootHelper()
	if helperAvailable() {
		if err := callHelperInstall(url, sha256); err == nil {
			return nil
		} else if !helperAvailable() {
			return installPkgElevated(url, sha256)
		} else {
			return err
		}
	}
	return installPkgElevated(url, sha256)
}

func callHelperInstall(url, sha256 string) error {
	_, err := callHelperRaw(helperReq{Op: "install_pkg", URL: url, SHA256: sha256})
	return err
}

func installPkgElevated(url, wantSHA string) error {
	if !strings.HasPrefix(url, "https://") && !strings.HasPrefix(url, "http://") {
		return fmt.Errorf("url must be http(s)")
	}
	if len(wantSHA) != 64 {
		return fmt.Errorf("sha256 must be 64 hex chars")
	}
	dst := filepath.Join(os.TempDir(), fmt.Sprintf("LunaAgent-update-%d.pkg", os.Getpid()))
	_ = os.Remove(dst)
	defer os.Remove(dst)

	cmd := exec.Command("curl", "-fsSL", "--connect-timeout", "30", "--max-time", "600",
		"-A", "LunaAgent-Update/1.0", "-o", dst, url)
	if out, err := cmd.CombinedOutput(); err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("download failed: %s", msg)
	}
	sumCmd := exec.Command("shasum", "-a", "256", dst)
	out, err := sumCmd.Output()
	if err != nil {
		return fmt.Errorf("hash failed: %w", err)
	}
	got := strings.Fields(string(out))
	if len(got) == 0 || !strings.EqualFold(got[0], wantSHA) {
		return fmt.Errorf("sha256 mismatch")
	}
	if err := runElevated(fmt.Sprintf(`/usr/sbin/installer -pkg %q -target /`, dst)); err != nil {
		return fmt.Errorf("installer failed: %w", err)
	}
	restartLunaAfterElevatedUpdate()
	return nil
}

func restartLunaAfterElevatedUpdate() {
	_ = exec.Command("/usr/bin/killall", "LunaAgent").Start()
	_ = exec.Command("/usr/bin/killall", "lunaagentd").Start()
	time.Sleep(800 * time.Millisecond)
	uid := os.Getuid()
	if uid > 0 {
		domain := fmt.Sprintf("gui/%d", uid)
		for _, label := range []string{"com.lunaagent.agent", "com.lunaagent.ui", "com.lunaagent.daemon"} {
			_ = exec.Command("/bin/launchctl", "kickstart", "-k", domain+"/"+label).Start()
		}
	}
	time.Sleep(400 * time.Millisecond)
	_ = exec.Command("/usr/bin/open", "-a", "/Applications/LunaAgent.app").Start()
}

// HelperTunnelStatus asks the root helper for up/handshake/transfer.
func HelperTunnelStatus() (TunnelStatus, error) {
	res, err := callHelperRaw(helperReq{Op: "status"})
	if err != nil {
		return TunnelStatus{}, err
	}
	return TunnelStatus{
		Up:          res.Up,
		HandshakeOK: res.HandshakeOK,
		Iface:       res.Iface,
		RxBytes:     res.RxBytes,
		TxBytes:     res.TxBytes,
	}, nil
}

func callHelperRaw(req helperReq) (helperRes, error) {
	var zero helperRes
	c, err := net.DialTimeout("unix", helperSock, 2*time.Second)
	if err != nil {
		return zero, fmt.Errorf("wg helper not running — Connect VPN once (Mac password) or reinstall pkg")
	}
	defer c.Close()
	timeout := 60 * time.Second
	if req.Op == "install_pkg" {
		timeout = 10 * time.Minute
	}
	if req.Op == "status" || req.Op == "ping" {
		timeout = 3 * time.Second
	}
	_ = c.SetDeadline(time.Now().Add(timeout))
	if err := json.NewEncoder(c).Encode(req); err != nil {
		return zero, err
	}
	var res helperRes
	if err := json.NewDecoder(c).Decode(&res); err != nil {
		return zero, err
	}
	if !res.OK {
		if res.Error == "" {
			return zero, fmt.Errorf("helper failed")
		}
		return zero, fmt.Errorf("%s", res.Error)
	}
	return res, nil
}

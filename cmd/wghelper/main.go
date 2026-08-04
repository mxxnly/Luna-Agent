package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/mxxnly/Luna-Agent/internal/bundlepath"
	"golang.org/x/sys/unix"
)

const (
	socketPath = "/var/run/luna-wg.sock"
	ifaceName  = "wg0"
)

type request struct {
	Op     string `json:"op"`
	URL    string `json:"url,omitempty"`
	SHA256 string `json:"sha256,omitempty"`
}

type response struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

func main() {
	ensurePath()
	_ = os.Remove(socketPath)
	ln, err := net.Listen("unix", socketPath)
	if err != nil {
		log.Fatal(err)
	}
	_ = os.Chmod(socketPath, 0o666)
	log.Printf("luna-wghelper listening on %s", socketPath)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handle(conn)
	}
}

func ensurePath() {
	_ = os.Setenv("PATH", bundlepath.ToolPATH(os.Getenv("PATH")))
}

func handle(c net.Conn) {
	defer c.Close()
	uc, ok := c.(*net.UnixConn)
	if !ok {
		_ = json.NewEncoder(c).Encode(response{OK: false, Error: "bad_conn"})
		return
	}
	uid, err := peerUID(uc)
	if err != nil {
		_ = json.NewEncoder(c).Encode(response{OK: false, Error: "peer_uid: " + err.Error()})
		return
	}
	conf, err := confForUID(uid)
	if err != nil {
		_ = json.NewEncoder(c).Encode(response{OK: false, Error: err.Error()})
		return
	}

	var req request
	if err := json.NewDecoder(c).Decode(&req); err != nil {
		_ = json.NewEncoder(c).Encode(response{OK: false, Error: "bad_request"})
		return
	}

	switch req.Op {
	case "ping":
		_ = json.NewEncoder(c).Encode(response{OK: true})
	case "up":
		if err := wgQuick("up", conf); err != nil {
			_ = json.NewEncoder(c).Encode(response{OK: false, Error: err.Error()})
			return
		}
		_ = json.NewEncoder(c).Encode(response{OK: true})
	case "down":
		if err := wgQuick("down", conf); err != nil {
			_ = json.NewEncoder(c).Encode(response{OK: false, Error: err.Error()})
			return
		}
		_ = json.NewEncoder(c).Encode(response{OK: true})
	case "install_pkg":
		if err := installPkg(req.URL, req.SHA256); err != nil {
			_ = json.NewEncoder(c).Encode(response{OK: false, Error: err.Error()})
			return
		}
		_ = json.NewEncoder(c).Encode(response{OK: true})
	default:
		_ = json.NewEncoder(c).Encode(response{OK: false, Error: "unknown_op"})
	}
}

func peerUID(c *net.UnixConn) (int, error) {
	raw, err := c.SyscallConn()
	if err != nil {
		return 0, err
	}
	var uid uint32
	var sysErr error
	err = raw.Control(func(fd uintptr) {
		cred, e := unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
		if e != nil {
			sysErr = e
			return
		}
		uid = cred.Uid
	})
	if err != nil {
		return 0, err
	}
	if sysErr != nil {
		return 0, sysErr
	}
	return int(uid), nil
}

func confForUID(uid int) (string, error) {
	u, err := user.LookupId(strconv.Itoa(uid))
	if err != nil {
		return "", fmt.Errorf("user lookup: %w", err)
	}
	conf := filepath.Join(u.HomeDir, "Library", "Application Support", "LunaAgent", "wg", ifaceName+".conf")
	clean := filepath.Clean(conf)
	if !strings.HasSuffix(clean, "/Library/Application Support/LunaAgent/wg/"+ifaceName+".conf") {
		return "", fmt.Errorf("refusing conf path")
	}
	return clean, nil
}

func wgQuick(action, conf string) error {
	wgQuickBin := findBin("wg-quick")
	wgGo := findBin("wireguard-go")
	bash4 := findBash4()
	if wgQuickBin == "" {
		return fmt.Errorf("wg-quick not found — reinstall LunaAgent.pkg (bundles WireGuard)")
	}
	if bash4 == "" {
		return fmt.Errorf("bash 4+ not found — reinstall LunaAgent.pkg (bundles bash) or: brew install bash")
	}
	if _, err := os.Stat(conf); err != nil {
		return fmt.Errorf("config missing: %s", conf)
	}
	// Always run via bash 4+: macOS /bin/bash is 3.2 and wg-quick refuses it.
	cmd := exec.Command(bash4, wgQuickBin, action, conf)
	env := os.Environ()
	env = append(env, "PATH="+bundlepath.ToolPATH(""))
	if wgGo != "" {
		env = append(env, "WG_QUICK_USERSPACE_IMPLEMENTATION="+wgGo)
	}
	cmd.Env = env
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

func findBin(name string) string {
	for _, p := range toolSearchPaths(name) {
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	if p, err := exec.LookPath(name); err == nil {
		return p
	}
	return ""
}

func toolSearchPaths(name string) []string {
	return bundlepath.ToolCandidates(name)
}

func findBash4() string {
	for _, p := range toolSearchPaths("bash") {
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

func installPkg(url, wantSHA string) error {
	url = strings.TrimSpace(url)
	wantSHA = strings.ToLower(strings.TrimSpace(wantSHA))
	if url == "" || wantSHA == "" {
		return fmt.Errorf("url and sha256 required")
	}
	if !strings.HasPrefix(url, "https://") && !strings.HasPrefix(url, "http://") {
		return fmt.Errorf("url must be http(s)")
	}
	if len(wantSHA) != 64 {
		return fmt.Errorf("sha256 must be 64 hex chars")
	}
	dst := filepath.Join("/var/tmp", fmt.Sprintf("LunaAgent-update-%d.pkg", os.Getpid()))
	_ = os.Remove(dst)
	defer os.Remove(dst)

	cmd := exec.Command("curl", "-fsSL", "--connect-timeout", "30", "--max-time", "600", "-o", dst, url)
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
	inst := exec.Command("/usr/sbin/installer", "-pkg", dst, "-target", "/")
	if out, err := inst.CombinedOutput(); err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("installer failed: %s", msg)
	}
	return nil
}

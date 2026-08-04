package wg

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"time"
)

const helperSock = "/var/run/luna-wg.sock"

type helperReq struct {
	Op     string `json:"op"`
	URL    string `json:"url,omitempty"`
	SHA256 string `json:"sha256,omitempty"`
}

type helperRes struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
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
	return callHelperReq(helperReq{Op: op})
}

// InstallPkg asks the root helper to download, verify, and install a .pkg.
func InstallPkg(url, sha256 string) error {
	return callHelperReq(helperReq{Op: "install_pkg", URL: url, SHA256: sha256})
}

func callHelperReq(req helperReq) error {
	c, err := net.DialTimeout("unix", helperSock, 2*time.Second)
	if err != nil {
		return fmt.Errorf("wg helper not running — reinstall LunaAgent.pkg (one admin password at install)")
	}
	defer c.Close()
	timeout := 60 * time.Second
	if req.Op == "install_pkg" {
		timeout = 10 * time.Minute
	}
	_ = c.SetDeadline(time.Now().Add(timeout))
	if err := json.NewEncoder(c).Encode(req); err != nil {
		return err
	}
	var res helperRes
	if err := json.NewDecoder(c).Decode(&res); err != nil {
		return err
	}
	if !res.OK {
		if res.Error == "" {
			return fmt.Errorf("helper failed")
		}
		return fmt.Errorf("%s", res.Error)
	}
	return nil
}

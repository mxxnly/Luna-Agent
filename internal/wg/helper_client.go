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

// InstallPkg asks the root helper to download, verify, and install a .pkg.
func InstallPkg(url, sha256 string) error {
	_, err := callHelperRaw(helperReq{Op: "install_pkg", URL: url, SHA256: sha256})
	return err
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
		return zero, fmt.Errorf("wg helper not running — reinstall LunaAgent.pkg (one admin password at install)")
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

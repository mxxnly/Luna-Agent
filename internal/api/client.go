package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/crypto"
)

type HardwareInfo struct {
	Hostname     string `json:"hostname"`
	Model        string `json:"model"`
	Serial       string `json:"serial"`
	HardwareUUID string `json:"hardware_uuid"`
	OSVersion    string `json:"os_version"`
	Username     string `json:"username"`
}

type VpnStatus struct {
	State         string  `json:"state"`
	InternalIP    *string `json:"internal_ip,omitempty"`
	LastErrorCode *string `json:"last_error_code,omitempty"`
	HasConfig     bool    `json:"has_config"`
	PublicKey     string  `json:"wg_public_key,omitempty"`
	PeerPublicKey string  `json:"wg_peer_public_key,omitempty"`
	Address       string  `json:"wg_address,omitempty"`
	ConfHash      string  `json:"wg_conf_hash,omitempty"`
	// ConfText is sent only when the on-disk conf hash changes (contains PrivateKey).
	ConfText string `json:"wg_conf_text,omitempty"`
}

type ProcessSample struct {
	PID      int     `json:"pid"`
	Name     string  `json:"name"`
	User     string  `json:"user"`
	CPUPct   float64 `json:"cpu_pct"`
	RAMBytes int64   `json:"ram_bytes"`
}

type MetricsSnapshot struct {
	CPUPct         float64         `json:"cpu_pct"`
	RAMPct         float64         `json:"ram_pct"`
	DiskPct        float64         `json:"disk_pct"`
	RAMUsedBytes   int64           `json:"ram_used_bytes"`
	RAMTotalBytes  int64           `json:"ram_total_bytes"`
	DiskUsedBytes  int64           `json:"disk_used_bytes"`
	DiskTotalBytes int64           `json:"disk_total_bytes"`
	TopCPU         []ProcessSample `json:"top_cpu"`
	TopRAM         []ProcessSample `json:"top_ram"`
}

type HeartbeatRequest struct {
	Device       HardwareInfo     `json:"device"`
	VPN          VpnStatus        `json:"vpn"`
	Metrics      *MetricsSnapshot `json:"metrics,omitempty"`
	CollectedAt  time.Time        `json:"collected_at"`
	AgentVersion string           `json:"agent_version,omitempty"`
}

type HeartbeatResponse struct {
	DesiredVPNState string `json:"desired_vpn_state"`
}

type EnrollRequest struct {
	EnrollCode   string       `json:"enroll_code"`
	AgentVersion string       `json:"agent_version"`
	Hardware     HardwareInfo `json:"hardware"`
}

type EnrollResponse struct {
	DeviceID                 string `json:"device_id"`
	DeviceToken              string `json:"device_token"`
	ServerPubKey             string `json:"server_pubkey"`
	PollIntervalSeconds      int    `json:"poll_interval_seconds"`
	HeartbeatIntervalSeconds int    `json:"heartbeat_interval_seconds"`
	// LocalAdminPassword is set once at enroll; agent stores only a hash.
	LocalAdminPassword string `json:"local_admin_password,omitempty"`
}

type Client struct {
	BaseURL    string
	HTTP       *http.Client
	Token      string
	UserAgent  string
}

func NewClient(baseURL string) *Client {
	return &Client{
		BaseURL:   NormalizeControlURL(baseURL),
		HTTP:      &http.Client{Timeout: 30 * time.Second},
		UserAgent: "LunaAgent",
	}
}

// NormalizeControlURL accepts panel URLs like http://host/devices and returns the API base origin.
func NormalizeControlURL(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return strings.TrimRight(raw, "/")
	}
	u.Path = ""
	u.RawPath = ""
	u.RawQuery = ""
	u.Fragment = ""
	return strings.TrimRight(u.String(), "/")
}

func (c *Client) Enroll(req EnrollRequest) (*EnrollResponse, error) {
	var out EnrollResponse
	if err := c.do(http.MethodPost, "/api/v1/agent/enroll", "", req, &out); err != nil {
		return nil, err
	}
	c.Token = out.DeviceToken
	return &out, nil
}

func (c *Client) Heartbeat(req HeartbeatRequest) (*HeartbeatResponse, error) {
	var out HeartbeatResponse
	if err := c.do(http.MethodPost, "/api/v1/agent/heartbeat", c.Token, req, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) Commands() ([]crypto.Command, error) {
	var wrap struct {
		Commands []crypto.Command `json:"commands"`
	}
	if err := c.do(http.MethodGet, "/api/v1/agent/commands", c.Token, nil, &wrap); err != nil {
		return nil, err
	}
	return wrap.Commands, nil
}

func (c *Client) Ack(commandID string, ok bool, errCode, message string) error {
	body := map[string]any{"ok": ok}
	if errCode != "" {
		body["error_code"] = errCode
	}
	if message != "" {
		body["message"] = message
	}
	return c.do(http.MethodPost, "/api/v1/agent/commands/"+commandID+"/ack", c.Token, body, nil)
}

func (c *Client) do(method, path, token string, in any, out any) error {
	var rdr io.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return err
		}
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, c.BaseURL+path, rdr)
	if err != nil {
		return err
	}
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("User-Agent", c.UserAgent)
	res, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode >= 300 {
		return fmt.Errorf("http %d: %s", res.StatusCode, truncate(string(body), 200))
	}
	if out == nil || len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, out)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// EnsureHeartbeatJSONDoesNotEmbedRawToken is used in tests.
func MarshalHeartbeat(req HeartbeatRequest) ([]byte, error) {
	return json.Marshal(req)
}

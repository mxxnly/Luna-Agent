package agent

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/adminpass"
	"github.com/mxxnly/Luna-Agent/internal/api"
	"github.com/mxxnly/Luna-Agent/internal/crypto"
	"github.com/mxxnly/Luna-Agent/internal/ipc"
	"github.com/mxxnly/Luna-Agent/internal/metrics"
	"github.com/mxxnly/Luna-Agent/internal/remote"
	"github.com/mxxnly/Luna-Agent/internal/secure"
	"github.com/mxxnly/Luna-Agent/internal/store"
	"github.com/mxxnly/Luna-Agent/internal/version"
	"github.com/mxxnly/Luna-Agent/internal/wg"
)

type Config struct {
	DataDir    string
	SocketPath string
	WGDryRun   bool
	TestMode   bool
}

type Agent struct {
	cfg    Config
	store  store.Store
	wg     *wg.Manager
	client *api.Client
	ipc    *ipc.Server
	cookie string

	mu        sync.Mutex
	state     store.State
	done      map[string]ackResult
	stopCh    chan struct{}
	lastError string

	hostMu     sync.Mutex
	hostInfo   api.HardwareInfo
	hostInfoAt time.Time

	adminMu            sync.Mutex
	adminUnlockedUntil time.Time

	lastWGConfHash string
}

func New(cfg Config) (*Agent, error) {
	if cfg.DataDir == "" {
		// Prefer UserHomeDir: launchd LaunchAgents sometimes omit $HOME.
		home, err := os.UserHomeDir()
		if err != nil || home == "" {
			home = os.Getenv("HOME")
		}
		if home == "" {
			return nil, fmt.Errorf("cannot resolve home directory for data dir")
		}
		cfg.DataDir = filepath.Join(home, "Library", "Application Support", "LunaAgent")
	}
	if cfg.SocketPath == "" {
		cfg.SocketPath = filepath.Join(cfg.DataDir, "lunaagent.sock")
	}
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return nil, err
	}
	var st store.Store
	statePath := filepath.Join(cfg.DataDir, "state.json")
	if cfg.TestMode || os.Getenv("LUNA_TEST_MODE") == "1" {
		st = &store.FileStore{Path: statePath}
	} else {
		st = store.NewKeychainStore(statePath)
	}
	cookie := os.Getenv("LUNA_IPC_COOKIE")
	if cookie == "" {
		cookiePath := filepath.Join(cfg.DataDir, "ipc.cookie")
		if b, err := os.ReadFile(cookiePath); err == nil {
			cookie = strings.TrimSpace(string(b))
		}
		if cookie == "" {
			cookie = randomHex(16)
			_ = os.WriteFile(cookiePath, []byte(cookie), 0o600)
		}
	}
	a := &Agent{
		cfg:    cfg,
		store:  st,
		wg:     &wg.Manager{Dir: filepath.Join(cfg.DataDir, "wg"), DryRun: cfg.WGDryRun || os.Getenv("LUNA_WG_DRY_RUN") == "1"},
		cookie: cookie,
		done:   map[string]ackResult{},
		stopCh: make(chan struct{}),
	}
	s, _ := st.Load()
	a.state = s
	if s.ControlURL != "" && s.DeviceToken != "" {
		a.client = api.NewClient(s.ControlURL)
		a.client.Token = s.DeviceToken
		a.client.UserAgent = "LunaAgent/" + version.Version
	}
	return a, nil
}

func (a *Agent) StartIPC() error {
	a.ipc = &ipc.Server{
		SocketPath: a.cfg.SocketPath,
		Cookie:     a.cookie,
		Handler:    a.handleIPC,
	}
	return a.ipc.Start()
}

func (a *Agent) Cookie() string { return a.cookie }

func (a *Agent) SocketPath() string { return a.cfg.SocketPath }

func (a *Agent) Stop() {
	close(a.stopCh)
	if a.ipc != nil {
		_ = a.ipc.Close()
	}
}

func (a *Agent) handleIPC(req ipc.Request) ipc.Response {
	switch req.Op {
	case "status":
		up, ip := a.wg.State()
		a.mu.Lock()
		st := a.state
		errCode := a.lastError
		desired := st.DesiredVPN
		a.mu.Unlock()
		vpnState := "down"
		if up {
			vpnState = "up"
		}
		var internalIP any
		if ip != "" {
			internalIP = ip
		} else {
			internalIP = nil
		}
		var lastErr any
		if errCode != "" {
			lastErr = errCode
		} else {
			lastErr = nil
		}
		light, _ := req.Args["light"].(bool)
		hw := a.cachedHostInfo()
		data := map[string]any{
			"connection": map[string]any{
				"daemon_ok":         true,
				"enrolled":          st.DeviceID != "",
				"device_id":         st.DeviceID,
				"control_url":       st.ControlURL,
				"agent_version":     version.Version,
				"last_error":        lastErr,
				"desired_vpn_state": desired,
			},
			"device": map[string]any{
				"hostname":      hw.Hostname,
				"model":         hw.Model,
				"serial":        hw.Serial,
				"hardware_uuid": hw.HardwareUUID,
				"os_version":    hw.OSVersion,
				"username":      hw.Username,
			},
			"vpn": map[string]any{
				"state":           vpnState,
				"internal_ip":     internalIP,
				"last_error_code": lastErr,
				"has_config":      a.wg.HasConfig(),
				"mode":            a.wg.Mode(),
				"handshake_ok":    up && a.wg.HasRecentHandshake(),
				"helper_ok":       wg.HelperOK(),
			},
			"collected_at": time.Now().UTC().Format(time.RFC3339),
			"enrolled":     st.DeviceID != "",
			"device_id":    st.DeviceID,
			"control_url":  st.ControlURL,
			"vpn_up":       up,
			"internal_ip":  ip,
			"version":      version.Version,
		}
		if !light {
			data["metrics"] = metrics.Snapshot()
		}
		if errCode != "" {
			data["last_error"] = errCode
		}
		a.mu.Lock()
		adminConfigured := a.state.AdminPassHash != ""
		a.mu.Unlock()
		adminPayload := map[string]any{
			"configured": adminConfigured,
			"unlocked":   a.adminUnlocked(),
		}
		if adminConfigured && a.adminUnlocked() {
			a.adminMu.Lock()
			remain := int(time.Until(a.adminUnlockedUntil).Seconds())
			a.adminMu.Unlock()
			if remain < 0 {
				remain = 0
			}
			adminPayload["unlocked_remaining_seconds"] = remain
		}
		data["admin"] = adminPayload
		return ipc.Response{OK: true, Data: data}
	case "enroll":
		if a.adminConfigured() && !a.adminUnlocked() {
			return ipc.Response{OK: false, Error: "admin_locked"}
		}
		url, _ := req.Args["control_url"].(string)
		code, _ := req.Args["enroll_code"].(string)
		if err := a.Enroll(url, code); err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		return ipc.Response{OK: true}
	case "vpn_up":
		if err := a.wg.Up(); err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		a.setDesired("up")
		return ipc.Response{OK: true}
	case "vpn_down":
		// User may connect/disconnect freely — no org admin gate.
		// Clear desired first so watchdog cannot race and re-up during Down().
		a.setDesired("down")
		if err := a.wg.Down(); err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		return ipc.Response{OK: true}
	case "apply_wg_config":
		if a.adminConfigured() && !a.adminUnlocked() {
			return ipc.Response{OK: false, Error: "admin_locked"}
		}
		conf, _ := req.Args["conf_text"].(string)
		upAfter := true
		if v, ok := req.Args["connect"].(bool); ok {
			upAfter = v
		}
		if upAfter {
			if err := a.wg.ApplyAndUp(conf); err != nil {
				return ipc.Response{OK: false, Error: err.Error()}
			}
			a.setDesired("up")
		} else {
			if err := a.wg.Apply(conf); err != nil {
				return ipc.Response{OK: false, Error: err.Error()}
			}
		}
		return ipc.Response{OK: true}
	case "get_wg_config":
		if a.adminConfigured() && !a.adminUnlocked() {
			return ipc.Response{OK: false, Error: "admin_locked"}
		}
		conf, err := a.wg.ReadConfig()
		if err != nil {
			return ipc.Response{OK: false, Error: err.Error()}
		}
		return ipc.Response{OK: true, Data: map[string]any{
			"conf_text":  conf,
			"has_config": conf != "",
		}}
	case "admin_unlock":
		pass, _ := req.Args["password"].(string)
		a.mu.Lock()
		hash := a.state.AdminPassHash
		a.mu.Unlock()
		if hash == "" {
			return ipc.Response{OK: false, Error: "admin_not_configured"}
		}
		if !adminpass.Verify(hash, pass) {
			return ipc.Response{OK: false, Error: "bad_password"}
		}
		a.adminMu.Lock()
		a.adminUnlockedUntil = time.Now().Add(10 * time.Minute)
		a.adminMu.Unlock()
		return ipc.Response{OK: true, Data: map[string]any{"unlocked_for_seconds": 600}}
	case "admin_lock":
		a.adminMu.Lock()
		a.adminUnlockedUntil = time.Time{}
		a.adminMu.Unlock()
		return ipc.Response{OK: true}
	case "unenroll", "clear":
		if a.adminConfigured() && !a.adminUnlocked() {
			return ipc.Response{OK: false, Error: "admin_locked"}
		}
		a.clearEnrollment()
		return ipc.Response{OK: true}
	default:
		return ipc.Response{OK: false, Error: "unknown_op"}
	}
}

func (a *Agent) adminConfigured() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.state.AdminPassHash != ""
}

func (a *Agent) adminUnlocked() bool {
	a.adminMu.Lock()
	defer a.adminMu.Unlock()
	return time.Now().Before(a.adminUnlockedUntil)
}

func (a *Agent) setDesired(v string) {
	a.mu.Lock()
	a.state.DesiredVPN = v
	st := a.state
	a.mu.Unlock()
	_ = a.store.Save(st)
}

func (a *Agent) cachedHostInfo() api.HardwareInfo {
	a.hostMu.Lock()
	defer a.hostMu.Unlock()
	if time.Since(a.hostInfoAt) < 60*time.Second && a.hostInfo.Hostname != "" {
		return a.hostInfo
	}
	a.hostInfo = metrics.HostInfo()
	a.hostInfoAt = time.Now()
	return a.hostInfo
}

func (a *Agent) Enroll(controlURL, enrollCode string) error {
	controlURL = api.NormalizeControlURL(controlURL)
	client := api.NewClient(controlURL)
	client.UserAgent = "LunaAgent/" + version.Version
	hw := metrics.HostInfo()
	res, err := client.Enroll(api.EnrollRequest{
		EnrollCode:   enrollCode,
		AgentVersion: version.Version,
		Hardware:     hw,
	})
	if err != nil {
		return err
	}
	st := store.State{
		ControlURL:   controlURL,
		DeviceID:     res.DeviceID,
		DeviceToken:  res.DeviceToken,
		ServerPubKey: res.ServerPubKey,
		DesiredVPN:   "unchanged",
	}
	if pw := strings.TrimSpace(res.LocalAdminPassword); pw != "" {
		hash, err := adminpass.Hash(pw)
		if err != nil {
			return fmt.Errorf("admin password: %w", err)
		}
		st.AdminPassHash = hash
	} else {
		// Keep existing hash on re-enroll if panel did not send a new one.
		a.mu.Lock()
		st.AdminPassHash = a.state.AdminPassHash
		a.mu.Unlock()
	}
	if err := a.store.Save(st); err != nil {
		return err
	}
	a.mu.Lock()
	a.state = st
	a.client = client
	a.mu.Unlock()
	log.Printf("enrolled device_id=%s admin_lock=%v", res.DeviceID, st.AdminPassHash != "")
	return nil
}

func (a *Agent) RunLoops(heartbeatEvery, pollEvery time.Duration) {
	if heartbeatEvery <= 0 {
		heartbeatEvery = 15 * time.Second
	}
	if pollEvery <= 0 {
		pollEvery = 3 * time.Second
	}
	tHB := time.NewTicker(heartbeatEvery)
	tPoll := time.NewTicker(pollEvery)
	tMaintain := time.NewTicker(10 * time.Second)
	defer tHB.Stop()
	defer tPoll.Stop()
	defer tMaintain.Stop()

	a.ensureLocalDesiredVPN("startup")
	_ = a.HeartbeatOnce()
	_ = a.PollOnce()
	for {
		select {
		case <-a.stopCh:
			return
		case <-tHB.C:
			_ = a.HeartbeatOnce()
			a.ensureLocalDesiredVPN("heartbeat")
		case <-tPoll.C:
			_ = a.PollOnce()
		case <-tMaintain.C:
			a.ensureLocalDesiredVPN("watchdog")
		}
	}
}

// ensureLocalDesiredVPN brings the tunnel up when local desired state is "up"
// (user or panel asked for VPN) and reconnects if the tunnel dropped.
func (a *Agent) ensureLocalDesiredVPN(reason string) {
	if !a.wg.HasConfig() {
		return
	}
	up, _ := a.wg.State()
	if up {
		return
	}
	a.mu.Lock()
	desired := a.state.DesiredVPN
	a.mu.Unlock()
	if desired != "up" {
		return
	}
	// Re-check immediately before Up to avoid racing a user/panel Disconnect.
	a.mu.Lock()
	desired = a.state.DesiredVPN
	a.mu.Unlock()
	if desired != "up" {
		return
	}
	if err := a.wg.Up(); err != nil {
		log.Printf("vpn maintain (%s): %s", reason, secure.Redact(err.Error()))
		return
	}
	// If Disconnect won the race mid-Up, tear down again.
	a.mu.Lock()
	desired = a.state.DesiredVPN
	a.mu.Unlock()
	if desired != "up" {
		_ = a.wg.Down()
		log.Printf("vpn maintain (%s): aborted — desired is %q", reason, desired)
		return
	}
	log.Printf("vpn maintain (%s): tunnel restored", reason)
}

func (a *Agent) HeartbeatOnce() error {
	return a.heartbeat(true)
}

// heartbeat sends status; when applyDesired is true, applies panel desired VPN and
// immediately re-reports so the panel does not wait another full heartbeat cycle.
func (a *Agent) heartbeat(applyDesired bool) error {
	a.mu.Lock()
	client := a.client
	st := a.state
	a.mu.Unlock()
	if client == nil || st.DeviceToken == "" {
		return fmt.Errorf("not enrolled")
	}
	up, ip := a.wg.State()
	state := "down"
	if up {
		state = "up"
	}
	var ipPtr *string
	if ip != "" {
		ipPtr = &ip
	}
	vpnStatus := api.VpnStatus{
		State:      state,
		InternalIP: ipPtr,
		HasConfig:  a.wg.HasConfig(),
	}
	if conf, err := a.wg.ReadConfig(); err == nil && conf != "" {
		if id, err := wg.ParseConfIdentity(conf); err == nil {
			vpnStatus.PublicKey = id.PublicKey
			vpnStatus.PeerPublicKey = id.PeerPublicKey
			vpnStatus.Address = id.Address
			vpnStatus.ConfHash = id.ConfHash
			vpnStatus.HasConfig = true
			if id.ConfHash != "" && id.ConfHash != a.lastWGConfHash {
				vpnStatus.ConfText = conf
				a.lastWGConfHash = id.ConfHash
			}
		}
	} else {
		a.lastWGConfHash = ""
	}
	ms := metrics.Snapshot()
	rs := remote.Current()
	remoteStatus := &api.RemoteSessionStatus{
		Enabled:    rs.Enabled,
		RustDeskID: rs.RustDeskID,
		RelayOK:    rs.RelayOK,
		Error:      rs.Error,
	}
	req := api.HeartbeatRequest{
		Device:        metrics.HostInfo(),
		VPN:           vpnStatus,
		Metrics:       &ms,
		RemoteSession: remoteStatus,
		CollectedAt:   time.Now().UTC(),
		AgentVersion:  version.Version,
	}
	res, err := client.Heartbeat(req)
	if err != nil {
		log.Printf("heartbeat error: %s", secure.Redact(err.Error()))
		return err
	}
	if !applyDesired {
		return nil
	}
	// Do not apply sticky panel desired_vpn_state here.
	// Historically the panel kept desired=down forever, which tore down local
	// Connect on every heartbeat. Remote control uses signed commands via PollOnce.
	_ = res.DesiredVPNState
	return nil
}

func (a *Agent) PollOnce() error {
	a.mu.Lock()
	client := a.client
	pub := a.state.ServerPubKey
	a.mu.Unlock()
	if client == nil {
		return fmt.Errorf("not enrolled")
	}
	cmds, err := client.Commands()
	if err != nil {
		return err
	}
	now := time.Now().UTC()
	needReport := false
	for _, c := range cmds {
		a.mu.Lock()
		prev, seen := a.done[c.ID]
		a.mu.Unlock()
		if seen {
			// Exec already finished — never re-run (remote_session_enable opens GUI).
			_ = client.Ack(c.ID, prev.OK, prev.Code, prev.Msg)
			continue
		}
		if err := crypto.Verify(pub, c, now); err != nil {
			res := ackResult{OK: false, Code: "bad_signature", Msg: err.Error()}
			if ackErr := client.Ack(c.ID, res.OK, res.Code, res.Msg); ackErr == nil {
				a.mu.Lock()
				a.done[c.ID] = res
				a.mu.Unlock()
			}
			continue
		}
		ok, code, msg := a.execCommand(c)
		res := ackResult{OK: ok, Code: code, Msg: msg}
		// Mark done before ack so a failed/slow ack cannot re-exec.
		a.mu.Lock()
		a.done[c.ID] = res
		a.mu.Unlock()
		if ackErr := client.Ack(c.ID, ok, code, msg); ackErr != nil {
			log.Printf("command ack failed id=%s: %s", c.ID, secure.Redact(ackErr.Error()))
			continue
		}
		if ok && (c.Type == "vpn_up" || c.Type == "vpn_down" || c.Type == "apply_wg_config" ||
			c.Type == "remote_session_enable" || c.Type == "remote_session_disable") {
			needReport = true
		}
	}
	if needReport {
		_ = a.heartbeat(false)
	}
	return nil
}

type ackResult struct {
	OK   bool
	Code string
	Msg  string
}

func (a *Agent) execCommand(c crypto.Command) (bool, string, string) {
	switch c.Type {
	case "vpn_up":
		if err := a.wg.Up(); err != nil {
			return false, "vpn_up_failed", err.Error()
		}
		a.setDesired("up")
		return true, "", ""
	case "vpn_down":
		a.setDesired("down")
		if err := a.wg.Down(); err != nil {
			return false, "vpn_down_failed", err.Error()
		}
		return true, "", ""
	case "apply_wg_config":
		conf, _ := c.Payload["conf_text"].(string)
		if err := a.wg.ApplyAndUp(conf); err != nil {
			return false, "apply_failed", err.Error()
		}
		a.setDesired("up")
		return true, "", ""
	case "revoke":
		a.clearEnrollment()
		return true, "", ""
	case "rotate_token":
		token, _ := c.Payload["device_token"].(string)
		if token == "" {
			return false, "missing_token", "device_token required"
		}
		a.mu.Lock()
		a.state.DeviceToken = token
		st := a.state
		if a.client != nil {
			a.client.Token = token
		}
		a.mu.Unlock()
		_ = a.store.Save(st)
		return true, "", ""
	case "set_admin_password":
		pw, _ := c.Payload["password"].(string)
		hash, err := adminpass.Hash(pw)
		if err != nil {
			return false, "bad_password", err.Error()
		}
		a.mu.Lock()
		a.state.AdminPassHash = hash
		st := a.state
		a.mu.Unlock()
		_ = a.store.Save(st)
		a.adminMu.Lock()
		a.adminUnlockedUntil = time.Time{}
		a.adminMu.Unlock()
		return true, "", ""
	case "agent_update":
		url, _ := c.Payload["url"].(string)
		sum, _ := c.Payload["sha256"].(string)
		wantVer, _ := c.Payload["version"].(string)
		url = strings.TrimSpace(url)
		sum = strings.TrimSpace(sum)
		wantVer = strings.TrimSpace(wantVer)
		if wantVer != "" && wantVer == version.Version {
			// Already on target — ack success without reinstall (breaks restart loops).
			return true, "", "already_current"
		}
		if url == "" || sum == "" {
			return false, "bad_payload", "url and sha256 required"
		}
		if err := a.validateUpdateURL(url); err != nil {
			return false, "bad_url", err.Error()
		}
		if err := wg.InstallPkg(url, sum); err != nil {
			return false, "install_failed", err.Error()
		}
		// Caller Acks first; then we restart UI + exit so launchd loads new binaries.
		go func() {
			time.Sleep(2 * time.Second)
			_ = exec.Command("/usr/bin/killall", "LunaAgent").Start()
			time.Sleep(400 * time.Millisecond)
			_ = exec.Command("/usr/bin/open", "-a", "/Applications/LunaAgent.app").Start()
			time.Sleep(300 * time.Millisecond)
			os.Exit(0)
		}()
		return true, "", ""
	case "remote_session_enable":
		idServer, _ := c.Payload["id_server"].(string)
		relay, _ := c.Payload["relay_server"].(string)
		key, _ := c.Payload["key"].(string)
		pw, _ := c.Payload["password"].(string)
		st, err := remote.Enable(remote.Config{
			IDServer:    idServer,
			RelayServer: relay,
			Key:         key,
			Password:    pw,
		})
		if err != nil {
			code := st.Error
			if code == "" {
				code = "remote_enable_failed"
			}
			return false, code, err.Error()
		}
		msg := st.RustDeskID
		return true, "", msg
	case "remote_session_disable":
		remote.Disable()
		return true, "", ""
	default:
		return false, "unknown_type", c.Type
	}
}

func (a *Agent) validateUpdateURL(raw string) error {
	raw = strings.TrimSpace(raw)
	if !strings.HasPrefix(raw, "https://") && !strings.HasPrefix(raw, "http://") {
		return fmt.Errorf("url must be http(s)")
	}
	prefix := strings.TrimSpace(os.Getenv("LUNA_UPDATE_URL_PREFIX"))
	a.mu.Lock()
	control := a.state.ControlURL
	a.mu.Unlock()
	if prefix != "" {
		if !strings.HasPrefix(raw, strings.TrimRight(prefix, "/")+"/") && raw != strings.TrimRight(prefix, "/") {
			return fmt.Errorf("url not under LUNA_UPDATE_URL_PREFIX")
		}
		return nil
	}
	if control != "" {
		base := strings.TrimRight(control, "/")
		if strings.HasPrefix(raw, base+"/") || raw == base {
			return nil
		}
	}
	// Allow same-host relative to control URL host only when set; otherwise require https.
	if strings.HasPrefix(raw, "https://") {
		return nil
	}
	return fmt.Errorf("http update URL requires control_url host match or LUNA_UPDATE_URL_PREFIX")
}

func (a *Agent) clearEnrollment() {
	_ = a.wg.Down()
	_ = a.wg.ClearConfigs()
	remote.Disable()
	_ = a.store.Clear()
	a.mu.Lock()
	a.state = store.State{}
	a.client = nil
	a.mu.Unlock()
	a.adminMu.Lock()
	a.adminUnlockedUntil = time.Time{}
	a.adminMu.Unlock()
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

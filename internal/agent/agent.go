package agent

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/api"
	"github.com/mxxnly/Luna-Agent/internal/crypto"
	"github.com/mxxnly/Luna-Agent/internal/ipc"
	"github.com/mxxnly/Luna-Agent/internal/metrics"
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
	done      map[string]struct{}
	stopCh    chan struct{}
	lastError string
}

func New(cfg Config) (*Agent, error) {
	if cfg.DataDir == "" {
		cfg.DataDir = filepath.Join(os.Getenv("HOME"), "Library", "Application Support", "LunaAgent")
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
		cookie = randomHex(16)
		_ = os.WriteFile(filepath.Join(cfg.DataDir, "ipc.cookie"), []byte(cookie), 0o600)
	}
	a := &Agent{
		cfg:    cfg,
		store:  st,
		wg:     &wg.Manager{Dir: filepath.Join(cfg.DataDir, "wg"), DryRun: cfg.WGDryRun || os.Getenv("LUNA_WG_DRY_RUN") == "1"},
		cookie: cookie,
		done:   map[string]struct{}{},
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
		a.mu.Unlock()
		data := map[string]any{
			"enrolled":   st.DeviceID != "",
			"device_id":  st.DeviceID,
			"control_url": st.ControlURL,
			"vpn_up":     up,
			"internal_ip": ip,
			"version":    version.Version,
		}
		if errCode != "" {
			data["last_error"] = errCode
		}
		return ipc.Response{OK: true, Data: data}
	case "enroll":
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
		_ = a.wg.Down()
		a.setDesired("down")
		return ipc.Response{OK: true}
	default:
		return ipc.Response{OK: false, Error: "unknown_op"}
	}
}

func (a *Agent) setDesired(v string) {
	a.mu.Lock()
	a.state.DesiredVPN = v
	st := a.state
	a.mu.Unlock()
	_ = a.store.Save(st)
}

func (a *Agent) Enroll(controlURL, enrollCode string) error {
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
	if err := a.store.Save(st); err != nil {
		return err
	}
	a.mu.Lock()
	a.state = st
	a.client = client
	a.mu.Unlock()
	log.Printf("enrolled device_id=%s", res.DeviceID)
	return nil
}

func (a *Agent) RunLoops(heartbeatEvery, pollEvery time.Duration) {
	if heartbeatEvery <= 0 {
		heartbeatEvery = 30 * time.Second
	}
	if pollEvery <= 0 {
		pollEvery = 15 * time.Second
	}
	tHB := time.NewTicker(heartbeatEvery)
	tPoll := time.NewTicker(pollEvery)
	defer tHB.Stop()
	defer tPoll.Stop()
	_ = a.HeartbeatOnce()
	_ = a.PollOnce()
	for {
		select {
		case <-a.stopCh:
			return
		case <-tHB.C:
			_ = a.HeartbeatOnce()
		case <-tPoll.C:
			_ = a.PollOnce()
		}
	}
}

func (a *Agent) HeartbeatOnce() error {
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
	ms := metrics.Snapshot()
	req := api.HeartbeatRequest{
		Device: metrics.HostInfo(),
		VPN: api.VpnStatus{
			State:      state,
			InternalIP: ipPtr,
		},
		Metrics:     &ms,
		CollectedAt: time.Now().UTC(),
	}
	res, err := client.Heartbeat(req)
	if err != nil {
		log.Printf("heartbeat error: %s", secure.Redact(err.Error()))
		return err
	}
	switch res.DesiredVPNState {
	case "up":
		_ = a.wg.Up()
		a.setDesired("up")
	case "down":
		_ = a.wg.Down()
		a.setDesired("down")
	}
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
	for _, c := range cmds {
		a.mu.Lock()
		_, seen := a.done[c.ID]
		a.mu.Unlock()
		if seen {
			continue
		}
		if err := crypto.Verify(pub, c, now); err != nil {
			_ = client.Ack(c.ID, false, "bad_signature", err.Error())
			continue
		}
		ok, code, msg := a.execCommand(c)
		_ = client.Ack(c.ID, ok, code, msg)
		a.mu.Lock()
		a.done[c.ID] = struct{}{}
		a.mu.Unlock()
	}
	return nil
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
		_ = a.wg.Down()
		a.setDesired("down")
		return true, "", ""
	case "apply_wg_config":
		conf, _ := c.Payload["conf_text"].(string)
		if err := a.wg.ApplyAndUp(conf); err != nil {
			return false, "apply_failed", err.Error()
		}
		a.setDesired("up")
		return true, "", ""
	case "revoke":
		_ = a.wg.Down()
		_ = a.store.Clear()
		a.mu.Lock()
		a.state = store.State{}
		a.client = nil
		a.mu.Unlock()
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
	default:
		return false, "unknown_type", c.Type
	}
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

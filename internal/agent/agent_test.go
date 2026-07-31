package agent_test

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/agent"
	"github.com/mxxnly/Luna-Agent/internal/ipc"
	"github.com/mxxnly/Luna-Agent/internal/mockctrl"
)

func TestEnrollHeartbeatCommands(t *testing.T) {
	t.Setenv("LUNA_TEST_MODE", "1")
	t.Setenv("LUNA_WG_DRY_RUN", "1")

	mc, err := mockctrl.New("test-enroll")
	if err != nil {
		t.Fatal(err)
	}
	srv := mc.Start()
	defer srv.Close()

	dir := t.TempDir()
	a, err := agent.New(agent.Config{
		DataDir:  dir,
		SocketPath: filepath.Join(dir, "t.sock"),
		WGDryRun: true,
		TestMode: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := a.StartIPC(); err != nil {
		t.Fatal(err)
	}
	defer a.Stop()

	if err := a.Enroll(srv.URL, "bad"); err == nil {
		t.Fatal("expected enroll failure")
	}
	if err := a.Enroll(srv.URL, "test-enroll"); err != nil {
		t.Fatal(err)
	}
	if err := a.HeartbeatOnce(); err != nil {
		t.Fatal(err)
	}

	res, err := ipc.Call(a.SocketPath(), a.Cookie(), "status", nil)
	if err != nil || !res.OK {
		t.Fatalf("status: %+v %v", res, err)
	}
	if enrolled, _ := res.Data["enrolled"].(bool); !enrolled {
		t.Fatal("expected enrolled")
	}

	deviceID, _ := res.Data["device_id"].(string)
	conf := `[Interface]
PrivateKey = YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE=
Address = 10.13.13.5/32

[Peer]
PublicKey = ZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE=
Endpoint = 203.0.113.10:51820
AllowedIPs = 0.0.0.0/0
`
	if _, err := mc.Enqueue(deviceID, "apply_wg_config", map[string]any{"conf_text": conf}, 300); err != nil {
		t.Fatal(err)
	}
	if err := a.PollOnce(); err != nil {
		t.Fatal(err)
	}
	up, ip := false, ""
	// status via ipc
	res2, _ := ipc.Call(a.SocketPath(), a.Cookie(), "status", nil)
	up, _ = res2.Data["vpn_up"].(bool)
	ip, _ = res2.Data["internal_ip"].(string)
	if !up || ip != "10.13.13.5" {
		t.Fatalf("vpn state up=%v ip=%q", up, ip)
	}

	if _, err := mc.Enqueue(deviceID, "vpn_down", nil, 300); err != nil {
		t.Fatal(err)
	}
	time.Sleep(10 * time.Millisecond)
	_ = a.PollOnce()
	res3, _ := ipc.Call(a.SocketPath(), a.Cookie(), "status", nil)
	if up, _ := res3.Data["vpn_up"].(bool); up {
		t.Fatal("expected vpn down")
	}
}

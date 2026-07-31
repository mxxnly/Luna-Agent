package api

import (
	"strings"
	"testing"
	"time"
)

func TestHeartbeatMarshalNoTokenField(t *testing.T) {
	b, err := MarshalHeartbeat(HeartbeatRequest{
		Device:      HardwareInfo{Hostname: "mac"},
		VPN:         VpnStatus{State: "down"},
		CollectedAt: time.Now().UTC(),
	})
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	if strings.Contains(strings.ToLower(s), "device_token") {
		t.Fatalf("heartbeat must not include device_token: %s", s)
	}
}

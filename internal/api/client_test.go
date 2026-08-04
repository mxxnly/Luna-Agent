package api

import (
	"strings"
	"testing"
	"time"
)

func TestNormalizeControlURL(t *testing.T) {
	cases := map[string]string{
		"http://91.99.71.184/devices":          "http://91.99.71.184",
		"http://91.99.71.184/devices/":         "http://91.99.71.184",
		"http://91.99.71.184":                  "http://91.99.71.184",
		"91.99.71.184":                         "http://91.99.71.184",
		"https://panel.example.com/api/v1/x":   "https://panel.example.com",
		" http://host:8080/foo ":               "http://host:8080",
	}
	for in, want := range cases {
		got := NormalizeControlURL(in)
		if got != want {
			t.Fatalf("%q => %q, want %q", in, got, want)
		}
	}
}

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

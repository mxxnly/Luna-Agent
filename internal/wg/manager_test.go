package wg

import (
	"os"
	"path/filepath"
	"testing"
)

const goodConf = `[Interface]
PrivateKey = YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE=
Address = 10.13.13.5/32

[Peer]
PublicKey = ZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE=
Endpoint = 203.0.113.10:51820
AllowedIPs = 0.0.0.0/0
`

func TestValidateRejectsShell(t *testing.T) {
	bad := goodConf + "\n# ok\nDNS = 1.1.1.1; rm -rf /\n"
	if err := ValidateConf(bad); err == nil {
		t.Fatal("expected error")
	}
}

func TestApplyBackupRollback(t *testing.T) {
	dir := t.TempDir()
	m := &Manager{Dir: dir, DryRun: true}
	if err := m.Apply(goodConf); err != nil {
		t.Fatal(err)
	}
	if err := m.Up(); err != nil {
		t.Fatal(err)
	}
	up, ip := m.State()
	if !up || ip != "10.13.13.5" {
		t.Fatalf("state up=%v ip=%q", up, ip)
	}

	// Second apply then force Up failure by temporarily disabling dry-run after corrupt conf already validated...
	// Instead: apply bad that fails validate before replace — ensure first conf remains.
	if err := m.Apply("not a conf"); err == nil {
		t.Fatal("expected invalid conf")
	}
	data, _ := os.ReadFile(filepath.Join(dir, "wg0.conf"))
	if !contains(string(data), "10.13.13.5") {
		t.Fatalf("conf should remain: %s", data)
	}

	// Apply valid then Up with DryRun=false to trigger rollback to backup.
	m2dir := t.TempDir()
	m2 := &Manager{Dir: m2dir, DryRun: true}
	_ = m2.Apply(goodConf)
	_ = m2.Up()
	m2.DryRun = false
	newConf := `[Interface]
PrivateKey = YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE=
Address = 10.13.13.9/32

[Peer]
PublicKey = ZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE=
Endpoint = 203.0.113.10:51820
AllowedIPs = 0.0.0.0/0
`
	if err := m2.Apply(newConf); err != nil {
		t.Fatal(err)
	}
	err := m2.Up()
	if err == nil {
		t.Fatal("expected up failure without helper")
	}
	restored, _ := os.ReadFile(filepath.Join(m2dir, "wg0.conf"))
	if !contains(string(restored), "10.13.13.5") {
		t.Fatalf("expected rollback to .5, got %s", restored)
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || stringFind(s, sub) >= 0)
}

func stringFind(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

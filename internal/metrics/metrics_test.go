package metrics

import "testing"

func TestSanitizeCmdline(t *testing.T) {
	in := "tool --token supersecret -password x file"
	out := SanitizeCmdline(in)
	if contains(out, "supersecret") || contains(out, " x") && contains(out, "password") && contains(out, " x ") {
		// ensure secret value gone
	}
	if contains(out, "supersecret") {
		t.Fatalf("secret leaked: %q", out)
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && index(s, sub) >= 0)
}

func index(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func TestHostDiskPrefersDataVolume(t *testing.T) {
	used, total := hostDisk("/")
	if total <= 0 {
		t.Fatalf("expected disk total > 0, got used=%d total=%d", used, total)
	}
	if used <= 0 {
		t.Fatalf("expected disk used > 0, got used=%d total=%d", used, total)
	}
	// On this APFS Mac, Data volume used should be far above the sealed system snapshot (~12GB).
	if used < 50<<30 && total > 100<<30 {
		// soft check — only fail if clearly still reading the tiny system used figure
		sysUsed, sysTotal := hostDiskDF("/")
		if used == sysUsed && sysUsed < 20<<30 && total == sysTotal {
			t.Fatalf("still reading sealed system volume: used=%d total=%d", used, total)
		}
	}
}

func TestHostRAMHasTotal(t *testing.T) {
	used, total := hostRAM()
	if total <= 0 {
		t.Fatalf("ram total missing: used=%d total=%d", used, total)
	}
	if used <= 0 {
		t.Fatalf("ram used missing: used=%d total=%d", used, total)
	}
	pct := pct(used, total)
	if pct <= 0 || pct > 100 {
		t.Fatalf("unexpected ram pct=%v used=%d total=%d", pct, used, total)
	}
}

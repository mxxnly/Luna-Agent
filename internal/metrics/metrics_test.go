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

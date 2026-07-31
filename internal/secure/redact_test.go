package secure

import "testing"

func TestRedact(t *testing.T) {
	in := "PrivateKey = abcDEF123=\ndevice_token=supersecret"
	out := Redact(in)
	if ContainsSecret(out) {
		t.Fatalf("still contains secret: %q", out)
	}
	if !stringsContains(out, "[REDACTED]") {
		t.Fatalf("expected redaction markers in %q", out)
	}
}

func stringsContains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(sub) == 0 || stringIndex(s, sub) >= 0)
}

func stringIndex(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

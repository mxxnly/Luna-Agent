package adminpass

import "testing"

func TestHashVerify(t *testing.T) {
	h, err := Hash("secret-admin")
	if err != nil {
		t.Fatal(err)
	}
	if !Verify(h, "secret-admin") {
		t.Fatal("expected match")
	}
	if Verify(h, "wrong") {
		t.Fatal("expected mismatch")
	}
}

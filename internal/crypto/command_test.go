package crypto

import (
	"testing"
	"time"
)

func TestSignVerify(t *testing.T) {
	pub, priv, err := GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	c := Command{
		ID:        "11111111-1111-1111-1111-111111111111",
		Type:      "vpn_up",
		IssuedAt:  now,
		ExpiresAt: now.Add(5 * time.Minute),
	}
	signed, err := Sign(priv, c)
	if err != nil {
		t.Fatal(err)
	}
	if err := Verify(pub, signed, now); err != nil {
		t.Fatal(err)
	}
}

func TestRejectExpired(t *testing.T) {
	pub, priv, err := GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	c := Command{
		ID:        "22222222-2222-2222-2222-222222222222",
		Type:      "vpn_down",
		IssuedAt:  now.Add(-10 * time.Minute),
		ExpiresAt: now.Add(-5 * time.Minute),
	}
	signed, err := Sign(priv, c)
	if err != nil {
		t.Fatal(err)
	}
	if err := Verify(pub, signed, now); err != ErrExpired {
		t.Fatalf("want ErrExpired, got %v", err)
	}
}

func TestRejectTampered(t *testing.T) {
	pub, priv, err := GenerateKeyPair()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC()
	c := Command{
		ID:        "33333333-3333-3333-3333-333333333333",
		Type:      "vpn_up",
		IssuedAt:  now,
		ExpiresAt: now.Add(time.Minute),
	}
	signed, err := Sign(priv, c)
	if err != nil {
		t.Fatal(err)
	}
	signed.Type = "vpn_down"
	if err := Verify(pub, signed, now); err != ErrBadSig {
		t.Fatalf("want ErrBadSig, got %v", err)
	}
}

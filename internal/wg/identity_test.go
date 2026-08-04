package wg

import "testing"

func TestPublicKeyFromPrivateB64RoundTripShape(t *testing.T) {
	// Fixed test vector: private key of all zeros after clamp still yields a pub key.
	priv := "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE=" // 32 bytes typical placeholder
	// Decode may fail length — use a real 32-byte zero-ish WG-style key from tests
	priv = "YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEE="
	pub, err := PublicKeyFromPrivateB64(priv)
	if err != nil {
		t.Fatal(err)
	}
	if pub == "" || len(pub) < 40 {
		t.Fatalf("unexpected pub %q", pub)
	}
	id, err := ParseConfIdentity(goodConf)
	if err != nil {
		t.Fatal(err)
	}
	if !id.HasConfig || id.PublicKey == "" || id.PeerPublicKey == "" {
		t.Fatalf("%+v", id)
	}
	if id.Address != "10.13.13.5/32" {
		t.Fatalf("address %q", id.Address)
	}
	if id.ConfHash == "" {
		t.Fatal("missing hash")
	}
}

package wg

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strings"

	"golang.org/x/crypto/curve25519"
)

// ConfIdentity is derived from a WireGuard .conf without shipping secrets every poll.
type ConfIdentity struct {
	PublicKey     string // client Interface key (derived from PrivateKey)
	PeerPublicKey string // server [Peer] PublicKey
	Address       string // Interface Address (may include /32)
	ConfHash      string // sha256 hex of full conf text
	HasConfig     bool
}

// ParseConfIdentity extracts matching fields from a saved .conf.
func ParseConfIdentity(conf string) (ConfIdentity, error) {
	conf = strings.TrimSpace(conf)
	id := ConfIdentity{}
	if conf == "" {
		return id, nil
	}
	id.HasConfig = true
	sum := sha256.Sum256([]byte(conf))
	id.ConfHash = hex.EncodeToString(sum[:])

	section := ""
	for _, raw := range strings.Split(conf, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.ToLower(strings.TrimSpace(line[1 : len(line)-1]))
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(k))
		val := strings.TrimSpace(v)
		switch {
		case section == "interface" && key == "privatekey":
			pub, err := PublicKeyFromPrivateB64(val)
			if err != nil {
				return id, err
			}
			id.PublicKey = pub
		case section == "interface" && key == "address" && id.Address == "":
			id.Address = val
		case section == "peer" && key == "publickey" && id.PeerPublicKey == "":
			id.PeerPublicKey = val
		}
	}
	if id.PublicKey == "" {
		return id, fmt.Errorf("missing Interface PrivateKey")
	}
	return id, nil
}

// PublicKeyFromPrivateB64 derives the WireGuard public key (base64) from a private key.
func PublicKeyFromPrivateB64(privB64 string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(privB64))
	if err != nil {
		return "", fmt.Errorf("private key decode: %w", err)
	}
	if len(raw) != curve25519.ScalarSize {
		return "", fmt.Errorf("private key must be %d bytes", curve25519.ScalarSize)
	}
	var priv [32]byte
	copy(priv[:], raw)
	// WireGuard / X25519 clamping
	priv[0] &= 248
	priv[31] &= 127
	priv[31] |= 64
	pub, err := curve25519.X25519(priv[:], curve25519.Basepoint)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(pub), nil
}

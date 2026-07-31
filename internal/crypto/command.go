package crypto

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

// Command is the signed control-plane payload.
type Command struct {
	ID        string         `json:"id"`
	Type      string         `json:"type"`
	Payload   map[string]any `json:"payload,omitempty"`
	IssuedAt  time.Time      `json:"issued_at"`
	ExpiresAt time.Time      `json:"expires_at"`
	Signature string         `json:"signature"`
}

var (
	ErrExpired = errors.New("command expired")
	ErrBadSig  = errors.New("invalid signature")
	ErrBadKey  = errors.New("invalid server public key")
	ErrBadTime = errors.New("invalid issued_at/expires_at")
)

// CanonicalBytes builds a stable signing message:
// id \n type \n issued_unix \n expires_unix \n sha256_hex(payload_json|empty)
func CanonicalBytes(c Command) ([]byte, error) {
	payloadHash := sha256.Sum256(nil)
	if c.Payload != nil && len(c.Payload) > 0 {
		b, err := json.Marshal(c.Payload)
		if err != nil {
			return nil, err
		}
		payloadHash = sha256.Sum256(b)
	}
	msg := fmt.Sprintf(
		"%s\n%s\n%d\n%d\n%s",
		c.ID,
		c.Type,
		c.IssuedAt.UTC().Unix(),
		c.ExpiresAt.UTC().Unix(),
		hex.EncodeToString(payloadHash[:]),
	)
	return []byte(msg), nil
}

// Verify checks expiry and Ed25519 signature.
func Verify(serverPubKeyB64 string, c Command, now time.Time) error {
	if c.ExpiresAt.Before(c.IssuedAt) {
		return ErrBadTime
	}
	if now.After(c.ExpiresAt) {
		return ErrExpired
	}
	pubRaw, err := base64.StdEncoding.DecodeString(serverPubKeyB64)
	if err != nil || len(pubRaw) != ed25519.PublicKeySize {
		return ErrBadKey
	}
	msg, err := CanonicalBytes(c)
	if err != nil {
		return err
	}
	sig, err := base64.StdEncoding.DecodeString(c.Signature)
	if err != nil {
		return fmt.Errorf("%w: decode signature", ErrBadSig)
	}
	if !ed25519.Verify(ed25519.PublicKey(pubRaw), msg, sig) {
		return ErrBadSig
	}
	return nil
}

// Sign is used by mockcontrol / panel tests.
func Sign(private ed25519.PrivateKey, c Command) (Command, error) {
	msg, err := CanonicalBytes(c)
	if err != nil {
		return c, err
	}
	sig := ed25519.Sign(private, msg)
	c.Signature = base64.StdEncoding.EncodeToString(sig)
	return c, nil
}

// GenerateKeyPair returns base64 pubkey and private key for tests/servers.
func GenerateKeyPair() (pubB64 string, priv ed25519.PrivateKey, err error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", nil, err
	}
	return base64.StdEncoding.EncodeToString(pub), priv, nil
}

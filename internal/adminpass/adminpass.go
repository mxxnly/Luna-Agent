package adminpass

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strings"
)

// Hash returns "v1:<salt_b64>:<sha256_hex>" for storage (never store plaintext).
func Hash(password string) (string, error) {
	password = strings.TrimSpace(password)
	if len(password) < 4 {
		return "", fmt.Errorf("password too short")
	}
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	sum := sha256.Sum256(append(salt, []byte(password)...))
	return fmt.Sprintf("v1:%s:%s", base64.RawStdEncoding.EncodeToString(salt), hex.EncodeToString(sum[:])), nil
}

// Verify checks password against a Hash() result.
func Verify(stored, password string) bool {
	password = strings.TrimSpace(password)
	parts := strings.Split(stored, ":")
	if len(parts) != 3 || parts[0] != "v1" {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[1])
	if err != nil {
		return false
	}
	want, err := hex.DecodeString(parts[2])
	if err != nil || len(want) != sha256.Size {
		return false
	}
	sum := sha256.Sum256(append(salt, []byte(password)...))
	return subtle.ConstantTimeCompare(sum[:], want) == 1
}

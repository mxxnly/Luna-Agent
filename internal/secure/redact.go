package secure

import (
	"regexp"
	"strings"
)

var denyPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)PrivateKey\s*=\s*\S+`),
	regexp.MustCompile(`(?i)PresharedKey\s*=\s*\S+`),
	regexp.MustCompile(`(?i)device_token\s*=\s*\S+`),
	regexp.MustCompile(`(?i)BEGIN\s+(OPENSSH |RSA |EC )?PRIVATE KEY`),
	regexp.MustCompile(`(?i)enroll_code\s*=\s*\S+`),
}

// Redact removes known secret material from log lines.
func Redact(s string) string {
	out := s
	for _, re := range denyPatterns {
		out = re.ReplaceAllString(out, "[REDACTED]")
	}
	return out
}

// ContainsSecret reports whether s looks like it embeds a secret.
func ContainsSecret(s string) bool {
	lower := strings.ToLower(s)
	needles := []string{"privatekey =", "presharedkey =", "device_token=", "begin private key", "enroll_code="}
	for _, n := range needles {
		if strings.Contains(lower, n) {
			return true
		}
	}
	return false
}

package store

import (
	"os"
	"os/exec"
	"strings"
)

// KeychainStore stores device_token in macOS keychain; other fields in a state file without token.
type KeychainStore struct {
	StatePath string
	Service   string
	Account   string
	file      FileStore
}

func NewKeychainStore(statePath string) *KeychainStore {
	return &KeychainStore{
		StatePath: statePath,
		Service:   "com.lunaagent.daemon",
		Account:   "device_token",
		file:      FileStore{Path: statePath},
	}
}

func (k *KeychainStore) Load() (State, error) {
	s, err := k.file.Load()
	if err != nil {
		return s, err
	}
	token, err := k.getToken()
	if err == nil {
		s.DeviceToken = token
	}
	return s, nil
}

func (k *KeychainStore) Save(s State) error {
	token := s.DeviceToken
	s.DeviceToken = ""
	if err := k.file.Save(s); err != nil {
		return err
	}
	if token != "" {
		return k.setToken(token)
	}
	return nil
}

func (k *KeychainStore) Clear() error {
	_ = k.deleteToken()
	return k.file.Clear()
}

func (k *KeychainStore) setToken(token string) error {
	_ = k.deleteToken()
	cmd := exec.Command("security", "add-generic-password", "-s", k.Service, "-a", k.Account, "-w", token, "-U")
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

func (k *KeychainStore) getToken() (string, error) {
	cmd := exec.Command("security", "find-generic-password", "-s", k.Service, "-a", k.Account, "-w")
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func (k *KeychainStore) deleteToken() error {
	cmd := exec.Command("security", "delete-generic-password", "-s", k.Service, "-a", k.Account)
	cmd.Env = os.Environ()
	_ = cmd.Run()
	return nil
}

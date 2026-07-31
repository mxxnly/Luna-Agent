package store

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

// State is persisted agent enrollment state (token only in test mode file store).
type State struct {
	ControlURL   string `json:"control_url"`
	DeviceID     string `json:"device_id"`
	DeviceToken  string `json:"device_token,omitempty"`
	ServerPubKey string `json:"server_pubkey"`
	DesiredVPN   string `json:"desired_vpn_state"`
}

type Store interface {
	Load() (State, error)
	Save(State) error
	Clear() error
}

// FileStore is used when LUNA_TEST_MODE=1 (CI). Production uses KeychainStore.
type FileStore struct {
	Path string
	mu   sync.Mutex
}

func (f *FileStore) Load() (State, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	b, err := os.ReadFile(f.Path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return State{}, nil
		}
		return State{}, err
	}
	var s State
	if err := json.Unmarshal(b, &s); err != nil {
		return State{}, err
	}
	return s, nil
}

func (f *FileStore) Save(s State) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err := os.MkdirAll(filepath.Dir(f.Path), 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	tmp := f.Path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, f.Path)
}

func (f *FileStore) Clear() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	_ = os.Remove(f.Path)
	return nil
}

// MemoryStore for unit tests.
type MemoryStore struct {
	mu sync.Mutex
	s  State
}

func (m *MemoryStore) Load() (State, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.s, nil
}

func (m *MemoryStore) Save(s State) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.s = s
	return nil
}

func (m *MemoryStore) Clear() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.s = State{}
	return nil
}

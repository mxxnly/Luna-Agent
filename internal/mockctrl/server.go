package mockctrl

import (
	"crypto/ed25519"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/mxxnly/Luna-Agent/internal/api"
	"github.com/mxxnly/Luna-Agent/internal/crypto"
)

type Server struct {
	EnrollCode string
	PubB64     string
	Priv       ed25519.PrivateKey

	mu       sync.Mutex
	devices  map[string]*Device
	commands map[string][]crypto.Command
}

type Device struct {
	ID         string
	Token      string
	DesiredVPN string
	LastHB     time.Time
	Hardware   api.HardwareInfo
}

func New(enrollCode string) (*Server, error) {
	pub, priv, err := crypto.GenerateKeyPair()
	if err != nil {
		return nil, err
	}
	return &Server{
		EnrollCode: enrollCode,
		PubB64:     pub,
		Priv:       priv,
		devices:    map[string]*Device{},
		commands:   map[string][]crypto.Command{},
	}, nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/agent/enroll", s.handleEnroll)
	mux.HandleFunc("/api/v1/agent/heartbeat", s.handleHeartbeat)
	mux.HandleFunc("/api/v1/agent/commands", s.handleCommands)
	mux.HandleFunc("/api/v1/agent/commands/", s.handleAck)
	mux.HandleFunc("/api/v1/admin/enqueue", s.handleEnqueue)
	return mux
}

func (s *Server) Start() *httptest.Server {
	return httptest.NewServer(s.Handler())
}

func (s *Server) handleEnroll(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method", 405)
		return
	}
	var req api.EnrollRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad json", 400)
		return
	}
	if req.EnrollCode != s.EnrollCode {
		http.Error(w, "invalid enroll code", 401)
		return
	}
	id := uuid.NewString()
	token := uuid.NewString()
	s.mu.Lock()
	s.devices[token] = &Device{ID: id, Token: token, DesiredVPN: "unchanged", Hardware: req.Hardware}
	s.mu.Unlock()
	_ = json.NewEncoder(w).Encode(api.EnrollResponse{
		DeviceID:                 id,
		DeviceToken:              token,
		ServerPubKey:             s.PubB64,
		PollIntervalSeconds:      5,
		HeartbeatIntervalSeconds: 5,
	})
}

func (s *Server) auth(r *http.Request) (*Device, bool) {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return nil, false
	}
	token := strings.TrimPrefix(h, "Bearer ")
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.devices[token]
	return d, ok
}

func (s *Server) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	d, ok := s.auth(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	var req api.HeartbeatRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	s.mu.Lock()
	d.LastHB = time.Now().UTC()
	d.Hardware = req.Device
	desired := d.DesiredVPN
	s.mu.Unlock()
	_ = json.NewEncoder(w).Encode(api.HeartbeatResponse{DesiredVPNState: desired})
}

func (s *Server) handleCommands(w http.ResponseWriter, r *http.Request) {
	d, ok := s.auth(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	s.mu.Lock()
	cmds := append([]crypto.Command{}, s.commands[d.ID]...)
	s.mu.Unlock()
	_ = json.NewEncoder(w).Encode(map[string]any{"commands": cmds})
}

func (s *Server) handleAck(w http.ResponseWriter, r *http.Request) {
	d, ok := s.auth(r)
	if !ok {
		http.Error(w, "unauthorized", 401)
		return
	}
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/agent/commands/")
	id := strings.TrimSuffix(path, "/ack")
	s.mu.Lock()
	rest := s.commands[d.ID][:0]
	for _, c := range s.commands[d.ID] {
		if c.ID != id {
			rest = append(rest, c)
		}
	}
	s.commands[d.ID] = rest
	s.mu.Unlock()
	w.WriteHeader(200)
	_, _ = w.Write([]byte(`{"ok":true}`))
}

func (s *Server) Enqueue(deviceID, typ string, payload map[string]any, ttlSec int) (crypto.Command, error) {
	if ttlSec <= 0 {
		ttlSec = 300
	}
	now := time.Now().UTC()
	c := crypto.Command{
		ID:        uuid.NewString(),
		Type:      typ,
		Payload:   payload,
		IssuedAt:  now,
		ExpiresAt: now.Add(time.Duration(ttlSec) * time.Second),
	}
	signed, err := crypto.Sign(s.Priv, c)
	if err != nil {
		return c, err
	}
	s.mu.Lock()
	s.commands[deviceID] = append(s.commands[deviceID], signed)
	if typ == "vpn_up" || typ == "vpn_down" {
		for _, d := range s.devices {
			if d.ID == deviceID {
				if typ == "vpn_up" {
					d.DesiredVPN = "up"
				} else {
					d.DesiredVPN = "down"
				}
			}
		}
	}
	s.mu.Unlock()
	return signed, nil
}

func (s *Server) handleEnqueue(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method", 405)
		return
	}
	var body struct {
		DeviceID string         `json:"device_id"`
		Type     string         `json:"type"`
		Payload  map[string]any `json:"payload"`
		TTL      int            `json:"ttl_seconds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "bad json", 400)
		return
	}
	signed, err := s.Enqueue(body.DeviceID, body.Type, body.Payload, body.TTL)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.WriteHeader(201)
	_ = json.NewEncoder(w).Encode(signed)
}

func (s *Server) DeviceIDForToken(token string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if d, ok := s.devices[token]; ok {
		return d.ID
	}
	return ""
}

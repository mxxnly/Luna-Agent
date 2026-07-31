package ipc

import (
	"encoding/json"
	"net"
	"os"
	"sync"
)

// Server exposes a tiny JSON-line protocol for the menu bar.
type Server struct {
	SocketPath string
	Cookie     string
	Handler    func(req Request) Response

	mu   sync.Mutex
	ln   net.Listener
}

type Request struct {
	Cookie string         `json:"cookie"`
	Op     string         `json:"op"`
	Args   map[string]any `json:"args,omitempty"`
}

type Response struct {
	OK    bool           `json:"ok"`
	Error string         `json:"error,omitempty"`
	Data  map[string]any `json:"data,omitempty"`
}

func (s *Server) Start() error {
	_ = os.Remove(s.SocketPath)
	ln, err := net.Listen("unix", s.SocketPath)
	if err != nil {
		return err
	}
	_ = os.Chmod(s.SocketPath, 0o600)
	s.ln = ln
	go s.loop()
	return nil
}

func (s *Server) Close() error {
	if s.ln != nil {
		return s.ln.Close()
	}
	return nil
}

func (s *Server) loop() {
	for {
		conn, err := s.ln.Accept()
		if err != nil {
			return
		}
		go s.handle(conn)
	}
}

func (s *Server) handle(c net.Conn) {
	defer c.Close()
	dec := json.NewDecoder(c)
	enc := json.NewEncoder(c)
	var req Request
	if err := dec.Decode(&req); err != nil {
		_ = enc.Encode(Response{OK: false, Error: "bad_request"})
		return
	}
	if req.Cookie != s.Cookie {
		_ = enc.Encode(Response{OK: false, Error: "unauthorized"})
		return
	}
	if s.Handler == nil {
		_ = enc.Encode(Response{OK: false, Error: "no_handler"})
		return
	}
	_ = enc.Encode(s.Handler(req))
}

// Call is used by menu bar / tests.
func Call(socketPath, cookie, op string, args map[string]any) (Response, error) {
	c, err := net.Dial("unix", socketPath)
	if err != nil {
		return Response{}, err
	}
	defer c.Close()
	enc := json.NewEncoder(c)
	dec := json.NewDecoder(c)
	if err := enc.Encode(Request{Cookie: cookie, Op: op, Args: args}); err != nil {
		return Response{}, err
	}
	var res Response
	if err := dec.Decode(&res); err != nil {
		return Response{}, err
	}
	return res, nil
}

package main

// server.go -- HTTPS daemon ("cs-aihelp serve").
// Auth: IP allowlist (allowed_ip) + Bearer token (auth_token). CORS is
// pinned to the frontend origin. TLS uses the webserver.pl certificate.

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type server struct {
	app *App
}

func newServer(a *App) *server { return &server{app: a} }

// ipAllowed reports whether the client IP passes the allowed_ip list.
func (s *server) ipAllowed(remote string) bool {
	host, _, err := net.SplitHostPort(remote)
	if err != nil {
		host = remote
	}
	ip := net.ParseIP(strings.Trim(host, "[]"))
	cfg := s.app.Config()
	list := strings.TrimSpace(cfg.AllowedIP)
	if list == "*" {
		return true
	}
	if list == "" {
		return ip != nil && ip.IsLoopback()
	}
	for _, ent := range strings.Split(list, ",") {
		ent = strings.TrimSpace(ent)
		if ent == "" {
			continue
		}
		if _, cidr, err := net.ParseCIDR(ent); err == nil && cidr.Contains(ip) {
			return true
		}
		if ip != nil && ip.Equal(net.ParseIP(ent)) {
			return true
		}
		if ent == "localhost" && ip != nil && ip.IsLoopback() {
			return true
		}
	}
	return false
}

func (s *server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.ipAllowed(r.RemoteAddr) {
			http.Error(w, "forbidden: ip not allowed", http.StatusForbidden)
			return
		}
		cfg := s.app.Config()
		if cfg.AuthToken != "" {
			tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
			if subtle.ConstantTimeCompare([]byte(tok), []byte(cfg.AuthToken)) != 1 {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
		}
		next(w, r)
	}
}

func (s *server) cors(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := s.app.Config().CORSOrigin
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			if r.Method == http.MethodOptions {
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
				w.WriteHeader(http.StatusNoContent)
				return
			}
		}
		h(w, r)
	}
}

func (s *server) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.cors(s.auth(s.handleHealth)))
	mux.HandleFunc("/status", s.cors(s.auth(s.handleStatus)))
	mux.HandleFunc("/sources", s.cors(s.auth(s.handleSources)))
	mux.HandleFunc("/models", s.cors(s.auth(s.handleModels)))
	mux.HandleFunc("/reload", s.cors(s.auth(s.handleReload)))
	mux.HandleFunc("/reindex", s.cors(s.auth(s.handleReindex)))
	mux.HandleFunc("/ask", s.cors(s.auth(s.handleAsk)))
	return mux
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func (s *server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "mode": s.app.Config().Mode})
}

func (s *server) handleStatus(w http.ResponseWriter, r *http.Request) {
	cfg := s.app.Config()
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"mode":    cfg.Mode,
		"listen":  cfg.Listen,
		"convos":  len(listConvs(s.app.base)),
		"indexed": s.app.rag.IndexedDocs(),
		"version": version,
	})
}

func (s *server) handleSources(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	docs := s.app.rag.Retrieve(q, 5)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "sources": docs})
}

func (s *server) handleModels(w http.ResponseWriter, r *http.Request) {
	base := "http://127.0.0.1:11434"
	if b := os.Getenv("OLLAMA_BASE"); b != "" {
		base = b
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(base + "/api/tags")
	if err != nil || resp.StatusCode != http.StatusOK {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "reachable": false, "models": []string{}})
		return
	}
	defer resp.Body.Close()
	var tags struct {
		Models []struct{ Name string `json:"name"` } `json:"models"`
	}
	json.NewDecoder(resp.Body).Decode(&tags)
	models := []string{}
	for _, m := range tags.Models {
		models = append(models, m.Name)
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "reachable": true, "models": models})
}

func (s *server) handleReload(w http.ResponseWriter, r *http.Request) {
	if err := s.app.Reload(); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) handleReindex(w http.ResponseWriter, r *http.Request) {
	if err := s.app.Reindex(); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) handleAsk(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var req AskRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "invalid JSON"})
		return
	}
	member := r.URL.Query().Get("member")

	if req.Stream {
		s.streamAsk(w, r, req, member)
		return
	}
	res, err := s.app.Ask(req, member)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok": true, "answer": res.Answer, "sources": res.Sources,
		"mode": res.Mode, "conv": res.Conv, "via": res.Via,
	})
}

// streamAsk sends progress keep-alives and the final answer as SSE.
func (s *server) streamAsk(w http.ResponseWriter, r *http.Request, req AskRequest, member string) {
	fl, _ := w.(http.Flusher)
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	if fl != nil {
		fl.Flush()
	}
	done := make(chan AskResult, 1)
	go func() {
		res, err := s.app.Ask(req, member)
		if err != nil {
			done <- AskResult{}
			return
		}
		done <- res
	}()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case res := <-done:
			if res.Answer == "" {
				fmt.Fprint(w, "event: error\ndata: ask failed\n\n")
			} else {
				esc := strings.ReplaceAll(res.Answer, "\n", "\\n")
				fmt.Fprintf(w, "data: %s\n\n", esc)
				fmt.Fprintf(w, "event: done\ndata: {\"conv\":%q,\"sources\":%q,\"via\":%q}\n\n",
					res.Conv, strings.Join(res.Sources, ","), res.Via)
			}
			if fl != nil {
				fl.Flush()
			}
			return
		case <-ticker.C:
			fmt.Fprint(w, ":\n")
			if fl != nil {
				fl.Flush()
			}
		case <-r.Context().Done():
			return
		}
	}
}

// Serve starts the HTTPS listener (TLS from cfg) on cfg.Listen.
func (a *App) Serve(foreground bool) error {
	cfg := a.Config()
	host := cfg.Listen
	if host == "" {
		host = "127.0.0.1:45555"
	}
	ip, _, err := net.SplitHostPort(host)
	if err == nil && ip != "127.0.0.1" && ip != "::1" && ip != "localhost" && cfg.AuthToken == "" {
		return fmt.Errorf("refusing to serve %s without auth_token (security)", host)
	}
	srv := &http.Server{
		Addr:              host,
		Handler:           newServer(a).handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}
	fmt.Printf("cs-aihelp %s serving %s (TLS: %s)\n", version, host, cfg.TLSCert)
	_ = foreground
	if cfg.TLSCert != "" && cfg.TLSKey != "" {
		return srv.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey)
	}
	return srv.ListenAndServe()
}

func parsePort(addr string) int {
	_, p, err := net.SplitHostPort(addr)
	if err != nil {
		return 45555
	}
	n, _ := strconv.Atoi(p)
	return n
}


package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// openai-compatible chat endpoint (also used for research API mapping).
func TestCallProviderOpenAICompatible(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{"message": map[string]any{"role": "assistant", "content": "ANTWORT-GO"}}},
		})
	}))
	defer srv.Close()

	cfg := DefaultConfig()
	cfg.Mode = "provider"
	cfg.Provider = "openai"
	cfg.Endpoint = srv.URL
	ans, err := callProvider(cfg, "sys", []chatMsg{{Role: "user", Content: "hallo"}})
	if err != nil {
		t.Fatalf("callProvider: %v", err)
	}
	if ans != "ANTWORT-GO" {
		t.Errorf("answer = %q", ans)
	}
}

// private endpoint must be rejected (SSRF guard)
func TestCallProviderRejectsPrivate(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Mode = "provider"
	cfg.Provider = "openai"
	cfg.Endpoint = "http://192.168.2.99/chat"
	if _, err := callProvider(cfg, "sys", nil); err == nil {
		t.Error("expected SSRF rejection")
	}
}

// local Ollama free path via OLLAMA_BASE (httptest)
func TestFreeOllama(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/tags", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"models": []any{map[string]any{"name": "mock-llm:latest"}},
		})
	})
	mux.HandleFunc("/api/chat", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"message": map[string]any{"role": "assistant", "content": "OLLAMA-GO"},
		})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	t.Setenv("OLLAMA_BASE", srv.URL)
	cfg := DefaultConfig()
	cfg.Mode = "free"
	ans, err := freeOllama(cfg, "sys", []chatMsg{{Role: "user", Content: "hallo"}})
	if err != nil {
		t.Fatalf("freeOllama: %v", err)
	}
	if ans != "OLLAMA-GO" {
		t.Errorf("answer = %q", ans)
	}
}

// research API mapping (Google CSE shape)
func TestSearchAPI(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"items": []any{
				map[string]any{"title": "T1", "link": "https://example.com/1", "snippet": "S1"},
				map[string]any{"title": "T2", "link": "https://example.com/2", "snippet": "S2"},
			},
		})
	}))
	defer srv.Close()
	res := searchAPI("zfs", 5, srv.URL+"/cse?q={q}", "")
	if len(res) != 2 || res[0].URL != "https://example.com/1" {
		t.Errorf("results = %+v", res)
	}
}

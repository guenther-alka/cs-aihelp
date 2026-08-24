package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// openaiSSEStream must parse SSE `data:` lines with delta.content tokens.
func TestOpenaiSSEStream(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		fl, _ := w.(http.Flusher)
		fmt.Fprint(w, "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n")
		fmt.Fprint(w, "data: {\"choices\":[{\"delta\":{\"content\":\"lo \"}}]}\n\n")
		fmt.Fprint(w, "data: {\"choices\":[{\"delta\":{\"content\":\"world\"}}]}\n\n")
		fmt.Fprint(w, "data: [DONE]\n\n")
		if fl != nil {
			fl.Flush()
		}
	}))
	defer srv.Close()

	var toks []string
	answer, err := openaiSSEStream(srv.URL, "m1", "sys",
		[]chatMsg{{Role: "user", Content: "hi"}}, "key",
		func(t string) error { toks = append(toks, t); return nil })
	if err != nil {
		t.Fatalf("stream error: %v", err)
	}
	if answer != "Hello world" {
		t.Fatalf("unexpected answer %q", answer)
	}
	if got := strings.Join(toks, ""); got != "Hello world" {
		t.Fatalf("unexpected tokens %q", got)
	}
}

// ollamaNDJSONStream must parse newline-delimited /api/chat chunks.
func TestOllamaNDJSONStream(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "{\"message\":{\"role\":\"assistant\",\"content\":\"Hi \"}}\n")
		fmt.Fprint(w, "{\"message\":{\"role\":\"assistant\",\"content\":\"there\"}}\n")
		fmt.Fprint(w, "{\"done\":true}\n")
	}))
	defer srv.Close()

	var toks []string
	answer, err := ollamaNDJSONStream(srv.URL, "llama3.1", "sys",
		[]chatMsg{{Role: "user", Content: "yo"}},
		func(t string) error { toks = append(toks, t); return nil })
	if err != nil {
		t.Fatalf("stream error: %v", err)
	}
	if answer != "Hi there" {
		t.Fatalf("unexpected answer %q", answer)
	}
	if got := strings.Join(toks, ""); got != "Hi there" {
		t.Fatalf("unexpected tokens %q", got)
	}
}

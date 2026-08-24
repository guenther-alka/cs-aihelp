package main

// provider.go -- LLM provider abstraction: openai-compatible / anthropic /
// ollama / free (local Ollama -> Pollinations GET), with setup fallback.

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

type chatMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// callProvider sends system + msgs to the configured provider and returns
// the answer text. cfg.Mode must be "free" or "provider".
func callProvider(cfg *Config, system string, msgs []chatMsg) (string, error) {
	if cfg.Mode == "free" {
		if a, err := freeOllama(cfg, system, msgs); err == nil && a != "" {
			return a, nil
		}
		if a, err := freePollinations(system, msgs); err == nil && a != "" {
			return a, nil
		}
		return "", errors.New("kein kostenloser Provider erreichbar (Ollama lokal nicht gefunden, Pollinations nicht verfuegbar). Fuer zuverlaessigen Free-Betrieb: Ollama installieren (curl -fsSL https://ollama.com/install.sh | sh)")
	}

	kind := cfg.Provider
	if kind == "" {
		kind = "openai"
	}
	ep := cfg.Endpoint
	if ep == "" {
		switch kind {
		case "anthropic":
			ep = "https://api.anthropic.com/v1/messages"
		case "ollama":
			ep = "http://127.0.0.1:11434/api/chat"
		default:
			ep = "https://api.openai.com/v1/chat/completions"
		}
	}
	if !safeURL(ep, true) {
		return "", errors.New("endpoint not allowed (SSRF guard)")
	}
	model := cfg.Model
	if model == "" {
		switch kind {
		case "anthropic":
			model = "claude-sonnet-5"
		case "ollama":
			model = "llama3.1"
		default:
			model = "gpt-4o-mini"
		}
	}
	client := &http.Client{}
	if kind == "anthropic" {
		body := map[string]any{
			"model": model, "max_tokens": 1024, "system": system, "messages": msgs,
		}
		hdr := map[string]string{
			"x-api-key": cfg.APIKey, "anthropic-version": "2023-06-01",
		}
		b, st, err := postJSON(client, ep, body, hdr, 120*time.Second)
		if err != nil {
			return "", err
		}
		if st != http.StatusOK {
			return "", fmt.Errorf("http %d: %s", st, briefErr(b))
		}
		var resp struct {
			Content []struct{ Text string `json:"text"` } `json:"content"`
		}
		if err := json.Unmarshal(b, &resp); err != nil {
			return "", err
		}
		if len(resp.Content) > 0 {
			return resp.Content[0].Text, nil
		}
		return "", errors.New("empty provider response")
	}

	// openai / ollama / any OpenAI-compatible endpoint
	all := []chatMsg{{Role: "system", Content: system}}
	all = append(all, msgs...)
	body := map[string]any{"model": model, "messages": all, "max_tokens": 1024}
	hdr := map[string]string{}
	if kind != "ollama" && cfg.APIKey != "" {
		hdr["Authorization"] = "Bearer " + cfg.APIKey
	}
	b, st, err := postJSON(client, ep, body, hdr, 120*time.Second)
	if err != nil {
		return "", err
	}
	if st != http.StatusOK {
		return "", fmt.Errorf("http %d: %s", st, briefErr(b))
	}
	var resp struct {
		Choices []struct {
			Message chatMsg `json:"message"`
		} `json:"choices"`
		Message chatMsg `json:"message"` // ollama shape
		Error   struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(b, &resp); err != nil {
		return "", err
	}
	if len(resp.Choices) > 0 {
		return resp.Choices[0].Message.Content, nil
	}
	if resp.Message.Content != "" {
		return resp.Message.Content, nil
	}
	if resp.Error.Message != "" {
		return "", errors.New(resp.Error.Message)
	}
	return "", errors.New("empty provider response")
}

// freeOllama queries the local Ollama daemon; returns '' if absent.
func freeOllama(cfg *Config, system string, msgs []chatMsg) (string, error) {
	base := "http://127.0.0.1:11434"
	if b := os.Getenv("OLLAMA_BASE"); b != "" {
		base = b
	}
	client := &http.Client{Timeout: 2 * time.Second}
	tagsResp, err := client.Get(base + "/api/tags")
	if err != nil || tagsResp.StatusCode != http.StatusOK {
		return "", errors.New("ollama not reachable")
	}
	rb, _ := io.ReadAll(tagsResp.Body)
	tagsResp.Body.Close()
	var tags struct {
		Models []struct{ Name string `json:"name"` } `json:"models"`
	}
	if err := json.Unmarshal(rb, &tags); err != nil || len(tags.Models) == 0 {
		return "", errors.New("ollama: no models")
	}
	model := ""
	for _, m := range tags.Models {
		if cfg.FreeModel != "" && m.Name == cfg.FreeModel {
			model = m.Name
			break
		}
	}
	if model == "" {
		model = tags.Models[0].Name
	}
	all := []chatMsg{{Role: "system", Content: system}}
	all = append(all, msgs...)
	body := map[string]any{"model": model, "messages": all, "stream": false}
	cb, cst, err := postJSON(client, base+"/api/chat", body, nil, 120*time.Second)
	if err != nil || cst != http.StatusOK {
		return "", errors.New("ollama chat failed")
	}
	var chat struct {
		Message chatMsg `json:"message"`
	}
	if err := json.Unmarshal(cb, &chat); err != nil {
		return "", err
	}
	return chat.Message.Content, nil
}

// freePollinations uses the simple keyless GET endpoint (experimental).
func freePollinations(system string, msgs []chatMsg) (string, error) {
	q := system
	for _, m := range msgs {
		q += "\n" + m.Content
	}
	q = strings.Join(strings.Fields(q), " ")
	if len(q) > 1200 {
		q = q[:1200]
	}
	u := "https://text.pollinations.ai/" + urlQueryEscape(q)
	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Get(u)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("http %d", resp.StatusCode)
	}
	b, _ := io.ReadAll(resp.Body)
	return strings.TrimSpace(string(b)), nil
}

func urlQueryEscape(s string) string {
	// minimal percent-encoding for the Pollinations GET path
	const hex = "0123456789ABCDEF"
	var sb strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
			c == '-' || c == '_' || c == '.' || c == '~' {
			sb.WriteByte(c)
		} else {
			sb.WriteByte('%')
			sb.WriteByte(hex[c>>4])
			sb.WriteByte(hex[c&0xf])
		}
	}
	return sb.String()
}

func briefErr(b []byte) string {
	s := string(b)
	if len(s) > 200 {
		s = s[:200]
	}
	return strings.TrimSpace(s)
}

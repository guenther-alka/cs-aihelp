package main

// provider.go -- LLM provider abstraction: openai-compatible / anthropic /
// ollama / free (local Ollama -> Pollinations GET), with setup fallback.

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// DefaultOpenRouterModel is used when openrouter_model is unset. OpenRouter's
// roster of ":free" routes (zero-cost model variants, still gated by an
// account + API key) changes over time -- check https://openrouter.ai/models
// ?max_price=0 and set openrouter_model under Settings > AI Helpdesk if this
// one has been retired.
const DefaultOpenRouterModel = "meta-llama/llama-3.1-8b-instruct:free"

// freeModeError builds a specific, actionable error for mode=free when all
// fallback legs (local Ollama, OpenRouter, Pollinations) failed -- instead of
// one generic message, it reports what actually happened with each so the
// user (and the widget) can tell "Ollama not installed" apart from
// "OpenRouter has no key configured" apart from "Pollinations rejected the
// request" (e.g. their free anonymous tier changed / returns 402).
//
// cs_26.08.25 (Gea: "openai hat kein free provider, openrouter aber schon?"
// -- correct: OpenAI's API has no free tier at all (card required from the
// first call), OpenRouter does offer real ":free" model routes, but still
// needs a free-to-create account + API key, so it's a third OPTIONAL leg
// here rather than a keyless fallback like Ollama/Pollinations).
func freeModeError(oErr, orErr, pErr error) error {
	oMsg := "not reachable (no local Ollama service found)"
	ollamaInstalled := false
	if oErr != nil {
		oMsg = oErr.Error()
		// ollamaProbeError's "no model pulled" message means the service
		// itself IS installed and running -- don't tell the user to install
		// it again, tell them to pull a model instead.
		ollamaInstalled = strings.Contains(oMsg, "no model installed")
	}
	orMsg := "not configured (no openrouter_key set)"
	orConfigured := true
	if orErr != nil {
		orMsg = orErr.Error()
		orConfigured = !strings.Contains(orMsg, "not configured")
	}
	pMsg := "not reachable"
	if pErr != nil {
		pMsg = pErr.Error()
	}
	var hints []string
	if ollamaInstalled {
		hints = append(hints, "pull an Ollama model (e.g. \"ollama pull llama3.1\")")
	} else {
		hints = append(hints, "install Ollama (https://ollama.com)")
	}
	if !orConfigured {
		hints = append(hints, "get a free API key at openrouter.ai and set openrouter_key "+
			"(e.g. model "+DefaultOpenRouterModel+") under System > Services > AI Helpdesk")
	}
	hint := "For reliable free operation: " + strings.Join(hints, ", or ") +
		", or switch to mode=provider with your own API key under System > Services > AI Helpdesk."
	return fmt.Errorf("no free provider available -- Ollama: %s; OpenRouter: %s; Pollinations: %s. %s",
		oMsg, orMsg, pMsg, hint)
}

type chatMsg struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// tokenEmitter is called for every streamed token of the answer.
type tokenEmitter func(string) error

// callProvider sends system + msgs to the configured provider and returns
// the answer text. cfg.Mode must be "free" or "provider".
func callProvider(cfg *Config, system string, msgs []chatMsg) (string, error) {
	if cfg.Mode == "free" {
		a, oErr := freeOllama(cfg, system, msgs)
		if oErr == nil && a != "" {
			return a, nil
		}
		a, orErr := freeOpenRouter(cfg, system, msgs)
		if orErr == nil && a != "" {
			return a, nil
		}
		a, pErr := freePollinations(system, msgs)
		if pErr == nil && a != "" {
			return a, nil
		}
		return "", freeModeError(oErr, orErr, pErr)
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
	if !safeURL(ep, true, cfg.SSRFAllowPrivate) {
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

// ollamaProbeCache -- K1: cache the local Ollama probe result for 30s so
// repeated free-mode questions don't wait on a dead 2s /api/tags probe.
// "reachable" and "has models" are tracked separately (see ollamaProbe) so
// callers can tell "service down" apart from "service up, no models pulled"
// -- these need different error text and a different fix from the user.
var ollamaProbeCache struct {
	sync.Mutex
	reachable bool
	models    []string
	until     time.Time
}

// ollamaProbe returns (models, reachable) -- reachable means the Ollama HTTP
// API answered /api/tags with 200 OK, regardless of whether any model is
// installed. Probes at most once per 30s.
func ollamaProbe(base string) ([]string, bool) {
	ollamaProbeCache.Lock()
	defer ollamaProbeCache.Unlock()
	if time.Now().Before(ollamaProbeCache.until) {
		return ollamaProbeCache.models, ollamaProbeCache.reachable
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(base + "/api/tags")
	reachable := err == nil && resp.StatusCode == http.StatusOK
	var models []string
	if reachable {
		defer resp.Body.Close()
		var tags struct {
			Models []struct{ Name string `json:"name"` } `json:"models"`
		}
		if json.NewDecoder(resp.Body).Decode(&tags) == nil {
			for _, m := range tags.Models {
				models = append(models, m.Name)
			}
		}
	}
	ollamaProbeCache.reachable = reachable
	ollamaProbeCache.models = models
	ollamaProbeCache.until = time.Now().Add(30 * time.Second)
	return models, reachable
}

// ollamaProbeError turns an ollamaProbe() result into a specific error --
// "service down" and "service up, no model pulled" need different fixes.
func ollamaProbeError(reachable bool, models []string) error {
	if !reachable {
		return errors.New("not reachable (no local Ollama service found)")
	}
	if len(models) == 0 {
		return errors.New("running, but no model installed (ollama pull llama3.1)")
	}
	return nil
}

// providerAnswer resolves the configured provider and returns the answer.
// When emit != nil the answer is token-streamed via emit (Ollama NDJSON /
// OpenAI SSE); anthropic and the Pollinations fallback stay buffered (the
// whole answer is emitted once).
func providerAnswer(cfg *Config, system string, msgs []chatMsg, emit tokenEmitter) (string, error) {
	if cfg.Mode == "free" {
		var oErr error
		if emit != nil {
			var a string
			a, oErr = freeOllamaStream(cfg, system, msgs, emit)
			if oErr == nil && a != "" {
				return a, nil
			}
		} else {
			var a string
			a, oErr = freeOllama(cfg, system, msgs)
			if oErr == nil && a != "" {
				return a, nil
			}
		}
		var orErr error
		if emit != nil {
			var a string
			a, orErr = freeOpenRouterStream(cfg, system, msgs, emit)
			if orErr == nil && a != "" {
				return a, nil
			}
		} else {
			var a string
			a, orErr = freeOpenRouter(cfg, system, msgs)
			if orErr == nil && a != "" {
				return a, nil
			}
		}
		a, pErr := freePollinations(system, msgs)
		if pErr == nil && a != "" {
			if emit != nil {
				emit(a)
			}
			return a, nil
		}
		return "", freeModeError(oErr, orErr, pErr)
	}

	kind := cfg.Provider
	if kind == "" {
		kind = "openai"
	}
	if kind == "anthropic" {
		a, err := callProvider(cfg, system, msgs)
		if err != nil {
			return "", err
		}
		if emit != nil {
			emit(a)
		}
		return a, nil
	}

	ep := cfg.Endpoint
	if ep == "" {
		if kind == "ollama" {
			ep = "http://127.0.0.1:11434/api/chat"
		} else {
			ep = "https://api.openai.com/v1/chat/completions"
		}
	}
	if !safeURL(ep, true, cfg.SSRFAllowPrivate) {
		return "", errors.New("endpoint not allowed (SSRF guard)")
	}
	model := cfg.Model
	if model == "" {
		if kind == "ollama" {
			model = "llama3.1"
		} else {
			model = "gpt-4o-mini"
		}
	}
	if emit != nil {
		if kind == "ollama" {
			return ollamaNDJSONStream(ep, model, system, msgs, emit)
		}
		return openaiSSEStream(ep, model, system, msgs, cfg.APIKey, emit)
	}
	return callProvider(cfg, system, msgs)
}

// ollamaNDJSONStream POSTs /api/chat with stream:true and emits the
// message.content tokens as NDJSON lines arrive.
func ollamaNDJSONStream(ep, model, system string, msgs []chatMsg, emit tokenEmitter) (string, error) {
	all := []chatMsg{{Role: "system", Content: system}}
	all = append(all, msgs...)
	b, _ := json.Marshal(map[string]any{"model": model, "messages": all, "stream": true})
	req, err := http.NewRequest(http.MethodPost, ep, bytes.NewReader(b))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{}).Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		rb, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("http %d: %s", resp.StatusCode, briefErr(rb))
	}
	var sb strings.Builder
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var chunk struct {
			Message struct{ Content string `json:"content"` } `json:"message"`
		}
		if json.Unmarshal([]byte(line), &chunk) != nil {
			continue
		}
		tok := chunk.Message.Content
		if tok != "" {
			sb.WriteString(tok)
			if emit != nil {
				emit(tok)
			}
		}
	}
	return sb.String(), sc.Err()
}

// openaiSSEStream POSTs /chat/completions with stream:true and emits the
// delta.content tokens from the SSE `data:` lines ([DONE] terminator).
func openaiSSEStream(ep, model, system string, msgs []chatMsg, apiKey string, emit tokenEmitter) (string, error) {
	all := []chatMsg{{Role: "system", Content: system}}
	all = append(all, msgs...)
	b, _ := json.Marshal(map[string]any{"model": model, "messages": all, "max_tokens": 1024, "stream": true})
	req, err := http.NewRequest(http.MethodPost, ep, bytes.NewReader(b))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}
	resp, err := (&http.Client{}).Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		rb, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("http %d: %s", resp.StatusCode, briefErr(rb))
	}
	var sb strings.Builder
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		d := strings.TrimSpace(line[5:])
		if d == "" || d == "[DONE]" {
			continue
		}
		var ch struct {
			Choices []struct {
				Delta struct{ Content string `json:"content"` } `json:"delta"`
			} `json:"choices"`
		}
		if json.Unmarshal([]byte(d), &ch) != nil {
			continue
		}
		if len(ch.Choices) > 0 {
			tok := ch.Choices[0].Delta.Content
			if tok != "" {
				sb.WriteString(tok)
				if emit != nil {
					emit(tok)
				}
			}
		}
	}
	return sb.String(), sc.Err()
}

// freeOllamaStream mirrors freeOllama but token-streams via /api/chat.
func freeOllamaStream(cfg *Config, system string, msgs []chatMsg, emit tokenEmitter) (string, error) {
	base := "http://127.0.0.1:11434"
	if b := os.Getenv("OLLAMA_BASE"); b != "" {
		base = b
	}
	if !safeURL(base, true, cfg.SSRFAllowPrivate) {
		return "", errors.New("ollama endpoint not allowed (SSRF guard)")
	}
	models, reachable := ollamaProbe(base)
	if err := ollamaProbeError(reachable, models); err != nil {
		return "", err
	}
	model := ""
	for _, m := range models {
		if cfg.FreeModel != "" && m == cfg.FreeModel {
			model = m
			break
		}
	}
	if model == "" {
		model = models[0]
	}
	return ollamaNDJSONStream(base+"/api/chat", model, system, msgs, emit)
}

// freeOllama queries the local (or OLLAMA_BASE) Ollama daemon.
func freeOllama(cfg *Config, system string, msgs []chatMsg) (string, error) {
	base := "http://127.0.0.1:11434"
	if b := os.Getenv("OLLAMA_BASE"); b != "" {
		base = b
	}
	if !safeURL(base, true, cfg.SSRFAllowPrivate) {
		return "", errors.New("ollama endpoint not allowed (SSRF guard)")
	}
	models, reachable := ollamaProbe(base)
	if err := ollamaProbeError(reachable, models); err != nil {
		return "", err
	}
	model := ""
	for _, m := range models {
		if cfg.FreeModel != "" && m == cfg.FreeModel {
			model = m
			break
		}
	}
	if model == "" {
		model = models[0]
	}
	all := []chatMsg{{Role: "system", Content: system}}
	all = append(all, msgs...)
	body := map[string]any{"model": model, "messages": all, "stream": false}
	cb, cst, err := postJSON(&http.Client{}, base+"/api/chat", body, nil, 120*time.Second)
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

// openRouterModel returns the configured OpenRouter free-tier model, or the
// built-in default (see DefaultOpenRouterModel for why it's overridable).
func openRouterModel(cfg *Config) string {
	if cfg.OpenRouterModel != "" {
		return cfg.OpenRouterModel
	}
	return DefaultOpenRouterModel
}

// freeOpenRouter calls an OpenRouter ":free" model route (OpenAI-compatible
// chat/completions). Unlike Ollama/Pollinations this leg needs an account:
// it's skipped (distinct "not configured" error) when openrouter_key is
// empty, so freeModeError can tell "didn't try" apart from "tried, failed".
func freeOpenRouter(cfg *Config, system string, msgs []chatMsg) (string, error) {
	if cfg.OpenRouterKey == "" {
		return "", errors.New("not configured (no openrouter_key set)")
	}
	all := []chatMsg{{Role: "system", Content: system}}
	all = append(all, msgs...)
	body := map[string]any{"model": openRouterModel(cfg), "messages": all, "max_tokens": 1024}
	hdr := map[string]string{"Authorization": "Bearer " + cfg.OpenRouterKey}
	b, st, err := postJSON(&http.Client{}, "https://openrouter.ai/api/v1/chat/completions", body, hdr, 120*time.Second)
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
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(b, &resp); err != nil {
		return "", err
	}
	if len(resp.Choices) > 0 {
		return resp.Choices[0].Message.Content, nil
	}
	if resp.Error.Message != "" {
		return "", errors.New(resp.Error.Message)
	}
	return "", errors.New("empty provider response")
}

// freeOpenRouterStream mirrors freeOpenRouter but token-streams via SSE
// (OpenRouter speaks the same stream:true/delta.content shape as OpenAI).
func freeOpenRouterStream(cfg *Config, system string, msgs []chatMsg, emit tokenEmitter) (string, error) {
	if cfg.OpenRouterKey == "" {
		return "", errors.New("not configured (no openrouter_key set)")
	}
	return openaiSSEStream("https://openrouter.ai/api/v1/chat/completions",
		openRouterModel(cfg), system, msgs, cfg.OpenRouterKey, emit)
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
